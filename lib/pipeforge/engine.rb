# frozen_string_literal: true

require_relative "source/reusable_io"
require_relative "source/csv_reader"
require_relative "column_value_analyzer"
require_relative "header_analyzer"
require_relative "target_schema"
require_relative "target_adapter"
require_relative "mapped_data_validator"
require_relative "run_processor"

module Pipeforge
  # The entry point of the engine. It is built for one source file and one target table, and runs
  # the stages on them: header analysis ({#analyze_headers}) and column values analysis
  # ({#analyze_column_values}).
  #
  # @example
  #   engine = Pipeforge::Engine.new(source_io: File.open("data/users.csv"), target_table: "users")
  #   header_analysis = engine.analyze_headers
  #   value_analysis = engine.analyze_column_values(
  #     mapped_columns: {"email" => {source_column: "Mail", value_mapping: {"N/A" => nil}}}
  #   )
  class Engine
    # The values +mode+ of {#run} can have.
    RUN_MODES = %i[dry_run run].freeze

    # @param source_io [IO] the CSV source, for example +File.open("data/users.csv")+. It must
    #   respond to +read+, +rewind+ and +seek+; it is wrapped in a {Source::ReusableIO}, so it
    #   can be read again.
    # @param target_table [String] the table the data will be loaded into
    #
    # @raise [TargetAdapterError] no adapter gem is loaded (+target_adapter_not_installed+)
    # @raise [Source::UnsupportedSourceError] the source is missing a method the engine needs
    def initialize(source_io:, target_table:)
      TargetAdapter.ensure_installed
      @source_reader = Source::CsvReader.new(source_io: Source::ReusableIO.new(io: source_io))
      @target_table = target_table
    end

    # Matches the columns of the source to the columns of the target table by name only, and
    # returns the best matches, in table order, with the metadata of each target column,
    # and the columns left unmatched. Only the header of the source and the schema of the target
    # are read, never any value or row.
    #
    # @return [HeaderAnalyzer::Result]
    # @raise [TargetSchemaError] the table or its model cannot be found
    # @raise [Source::EmptySourceError] the source has no header row
    # @raise [Source::InvalidHeaderError] a header cell is blank or a name appears twice
    def analyze_headers
      HeaderAnalyzer.call(
        source_headers: @source_reader.headers,
        source_identifier: @source_reader.identifier,
        target_schema: target_schema
      )
    end

    # Measures the mapped columns of the source file: how many values are empty, how many fit
    # the type of the target column, and which distinct values do and do not fit. The type, size
    # and precision of each target column come from the schema of the target table.
    #
    # With a value mapping, each value is measured as the value it maps to, so the counts show
    # what would be loaded, and the mapping comes back in the result. The rows are read again on
    # every call, so an edited mapping can be measured again.
    #
    # @param mapped_columns [Hash{String => Hash}] target column => {source_column:,
    #   value_mapping: {value in the file => value to load}}, a plain Hash the caller builds (the
    #   header result is not passed in). A source column may be given to several target columns.
    #   Every required target column (see {TargetColumn}) needs an entry. +value_mapping+ is
    #   optional (leave the key out for none; +nil+ is an error), its keys are turned into text,
    #   and a value that maps to nil or a blank is loaded as empty. The entries must not be frozen: the type metadata of each target column is added
    #   to them (see {#add_type_metadata}), then the position of the source column and a type
    #   checker, and the keys of their value mapping are replaced by text.
    # @return [ColumnValueAnalyzer::Result]
    # @raise [TargetSchemaError] the table or its model cannot be found
    # @raise [Source::EmptySourceError] the source has no header row
    # @raise [Source::InvalidHeaderError] a header cell is blank or a name appears twice
    # @raise [InvalidMappedColumnsError] the mapped columns, an entry or a value mapping is not a
    #   Hash; a target column is not in the schema; an entry has no source column or one that is
    #   not in the file; or a required target column has no entry. Every such mistake is listed,
    #   except that mapped columns that are not a Hash are reported alone.
    # @raise [Source::MalformedSourceError] a row cannot be parsed
    def analyze_column_values(mapped_columns:)
      check_mapped_columns(mapped_columns: mapped_columns)

      add_type_metadata(mapped_columns: mapped_columns, target_columns: target_columns_by_name)
      convert_value_mapping_keys(mapped_columns: mapped_columns)

      ColumnValueAnalyzer.call(
        source_reader: @source_reader, mapped_columns: mapped_columns,
        model_adapter: model_adapter
      )
    end

    # Validates every row of the source against the target and writes the ones that pass, one row at
    # a time, and counts the rows written and the rows that failed. The rows are read in chunks, and
    # each chunk's result, with its failed rows, is yielded to the block as soon as the chunk is done.
    #
    # A +:run+ keeps what it writes, each row in its own transaction. A +:dry_run+ writes the same
    # rows inside one transaction that is rolled back at the end, so the target is unchanged and the
    # failed rows are the same; the block is called inside that transaction, so it must not write to
    # the target database.
    #
    # @param mode [Symbol] +:dry_run+ or +:run+
    # @param mapped_columns [Hash{String => Hash}] as in {#analyze_column_values}
    # @param offset [Integer] rows to skip before the first one processed; the +row_number+ of the last
    #   row of an earlier run continues that run
    # @param chunk_size [Integer] rows read, processed and yielded at a time; the +execution.chunk_size+
    #   setting when not given
    # @yieldparam chunk_result [RunProcessor::ChunkResult] the outcome of one chunk
    # @return [RunProcessor::RunResult]
    # @raise [ArgumentError] +mode+ is not +:dry_run+ or +:run+, +offset+ is not a whole number of at least 0,
    #   or +chunk_size+ is not a whole number of at least 1; every bad one is in the message
    # @raise [TargetSchemaError] the table or its model cannot be found
    # @raise [InvalidMappedColumnsError] as in {#analyze_column_values}
    # @raise [Source::MalformedSourceError] a row cannot be parsed
    def run(mode:, mapped_columns:, offset: 0, chunk_size: Configuration.execution.chunk_size, &on_chunk)
      check_run_arguments(mode: mode, offset: offset, chunk_size: chunk_size)
      check_mapped_columns(mapped_columns: mapped_columns)
      convert_value_mapping_keys(mapped_columns: mapped_columns)

      RunProcessor.call(
        source_reader: @source_reader, mapped_columns: mapped_columns, target_schema: target_schema,
        offset: offset, chunk_size: chunk_size, mode: mode, model_adapter: model_adapter, &on_chunk
      )
    end

    private

    # Stops with an ArgumentError that lists every argument of {#run} that cannot be used, or does nothing.
    #
    # @raise [ArgumentError] +mode+ is not +:dry_run+ or +:run+, +offset+ is not a whole number of at least
    #   0, or +chunk_size+ is not a whole number of at least 1
    def check_run_arguments(mode:, offset:, chunk_size:)
      messages = []

      unless RUN_MODES.include?(mode)
        messages << "mode must be :dry_run or :run, got #{mode.inspect}"
      end

      unless Utilities.non_negative_whole_number?(value: offset)
        messages << "offset must be a whole number of at least 0, got #{offset.inspect}"
      end

      unless Utilities.positive_whole_number?(value: chunk_size)
        messages << "chunk_size must be a whole number of at least 1, got #{chunk_size.inspect}"
      end

      raise ArgumentError, messages.join("; ") unless messages.empty?
    end

    # The columns of the target table by name.
    def target_columns_by_name
      target_columns = {}
      target_schema.columns.each { |target_column| target_columns[target_column.name] = target_column }

      target_columns
    end

    # Stops with every mistake in the mapped columns, or does nothing when there is none.
    def check_mapped_columns(mapped_columns:)
      MappedDataValidator.new(
        source_header_names: @source_reader.headers,
        target_column_names: target_columns_by_name.keys,
        required_target_column_names: target_schema.columns.select(&:required).map(&:name),
        target_table: @target_table
      ).call(mapped_columns: mapped_columns)
    end

    # The adapter's object for the target table, which casts texts and builds records.
    def model_adapter
      if @model_adapter.nil?
        # Kept only once the adapter has answered, so a failed ask is asked again on the next call.
        @model_adapter = TargetAdapter.model_adapter(target_table: @target_table)
      end

      @model_adapter
    end

    # The schema of the target table. The adapter is asked on the first call and the answer is
    # kept. A failed read is not kept, so the next call asks again.
    def target_schema
      if @target_schema.nil?
        @target_schema = TargetAdapter.schema(target_table: @target_table)
      end

      @target_schema
    end

    # The values of the file are text, so the keys of every value mapping are turned into text
    # (+1+ and +"1"+ are the same key; when two keys give the same text, the later one is used).
    # It replaces the value mapping in the entries it is given.
    def convert_value_mapping_keys(mapped_columns:)
      mapped_columns.each_value do |mapped_column|
        next if mapped_column[:value_mapping].nil?

        mapped_column[:value_mapping] = mapped_column[:value_mapping].transform_keys(&:to_s)
      end
    end

    # Adds the type metadata of the target column (its type, limit, unsigned, length, precision, scale and
    # enum values), taken from the schema, to each entry of the mapped columns. It changes the
    # entries it is given: a +type+ the caller sent is replaced by the type of the schema.
    def add_type_metadata(mapped_columns:, target_columns:)
      mapped_columns.each do |target_column_name, mapped_column|
        target_column = target_columns.fetch(target_column_name)

        mapped_column.merge!(
          type: target_column.type,
          limit: target_column.limit,
          unsigned: target_column.unsigned,
          max_length: target_column.max_length,
          precision: target_column.precision,
          scale: target_column.scale,
          enum_values: target_column.enum_values
        )
      end
    end
  end
end
