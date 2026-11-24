# frozen_string_literal: true

require_relative "source/reusable_io"
require_relative "source/csv_reader"
require_relative "column_value_analyzer"
require_relative "header_analyzer"
require_relative "target_schema"
require_relative "mapped_data_validator"
require_relative "run_processor"

module Pipeforge
  # The entry point of the engine. It is built for one source file and one target table, and runs
  # the stages on them: header analysis ({#analyze_headers}) and column values analysis
  # ({#analyze_column_values}).
  #
  # @example
  #   engine = Pipeforge::Engine.new(source_io: File.open("data/users.csv"), target_model_name: "User")
  #   header_analysis = engine.analyze_headers
  #   value_analysis = engine.analyze_column_values(
  #     mapped_columns: {"email" => {source_column_name: "Mail", value_mapping: {"N/A" => nil}}}
  #   )
  #
  # The engine reaches the target through a target class that an adapter gem installs when it is
  # loaded ({.install_target}); the engine builds one target from it for its target model. The core
  # names no database library. A target answers +schema+ (the {TargetSchema} of the model's table),
  # +cast_value(column_name:, value:)+ (a {CastResult}: whether the model can cast a value and what it
  # would load, in Ruby and in JSON types), +build_record(attributes:)+ (the target's record of one
  # row), +preload_parents(records:)+ (loads the parents a chunk needs) and
  # +transaction(rollback_at_end:)+ (runs a block inside one transaction of the target database,
  # rolled back when the block ends if +rollback_at_end+ is true). A record answers +valid?+,
  # +errors+ (a Hash, target column name => its {ErrorCatalog::ColumnError}), +add_error(error:)+, +attributes+,
  # +json_attributes+ and +load+ (see {RunProcessor::ChunkProcessor}).
  class Engine
    # The values +mode+ of {#run} can have.
    RUN_MODES = %i[dry_run run].freeze

    class << self
      # Gives the engine the target class of an adapter gem. The gem entry calls it once, when the
      # gem is loaded. Every engine builds its own target from this class, for one target model, so
      # the class keeps no state of its own. If two adapter gems are loaded, the last one installed
      # is used.
      #
      # @api private
      # @param target_class [Class] follows the target contract above and is built with
      #   +new(target_model_name:)+
      # @return [void]
      def install_target(target_class:)
        @target_class = target_class
      end

      # @api private
      # @return [Class, nil] the class given to {.install_target}; nil before it is called
      attr_reader :target_class
    end

    # @param source_io [IO] the CSV source, for example +File.open("data/users.csv")+. It must
    #   respond to +read+, +rewind+ and +seek+; it is wrapped in a {Source::ReusableIO}, so it
    #   can be read again.
    # @param target_model_name [String] the name of the model the data will be loaded through,
    #   for example +"User"+
    #
    # @raise [ArgumentError] the source is missing a method the engine needs (+read+, +rewind+ or +seek+)
    def initialize(source_io:, target_model_name:)
      @source_reader = Source::CsvReader.new(source_io: Source::ReusableIO.new(io: source_io))
      @target_model_name = target_model_name
    end

    # Matches the columns of the source to the columns of the target table by name only, and
    # returns the best matches, in table order, with the metadata of each target column,
    # and the columns left unmatched. Only the header of the source and the schema of the target
    # are read, never any value or row.
    #
    # @return [HeaderAnalyzer::Result]
    # @raise [TargetSchemaError] the table or its model cannot be found
    # @raise [Source::Error] the source has no header row, or a header cell is blank or a name appears twice
    def analyze_headers
      HeaderAnalyzer.call(
        source_headers: @source_reader.headers,
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
    # @param mapped_columns [Hash{String => Hash}] target column => {source_column_name:,
    #   value_mapping: {value in the file => value to load}}, a plain Hash the caller builds (the
    #   header result is not passed in). A source column may be given to several target columns.
    #   Every required target column (see {TargetColumn}) needs an entry. +value_mapping+ is
    #   optional (leave the key out for none; +nil+ is an error), its keys are turned into text, and a
    #   value that maps to nil or a blank is loaded as empty. The caller's Hash is not changed (see
    #   {ResolvedMappedColumn}); the type and the limits of each target column come from the schema of the table.
    # @return [ColumnValueAnalyzer::Result]
    # @raise [TargetSchemaError] the table or its model cannot be found
    # @raise [Source::Error] the source has no header row, a header cell is blank or a name appears twice, or a row
    #   cannot be parsed or has more cells than the header
    # @raise [InvalidMappedColumnsError] the mapped columns, an entry or a value mapping is not a
    #   Hash; a target column is not in the schema; an entry has no source column or one that is
    #   not in the file; or a required target column has no entry. Every such mistake is listed,
    #   except that mapped columns that are not a Hash are reported alone.
    def analyze_column_values(mapped_columns:)
      check_mapped_columns(mapped_columns: mapped_columns)

      ColumnValueAnalyzer.call(
        source_reader: @source_reader, resolved_mapped_columns: resolve_mapped_columns(mapped_columns: mapped_columns),
        target: target
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
    # @param mapped_columns [Hash{String => Hash}] as in {#analyze_column_values}; the caller's Hash is not changed
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
    # @raise [Source::Error] a row cannot be parsed, or has more cells than the header
    def run(mode:, mapped_columns:, offset: 0, chunk_size: Configuration.execution.chunk_size, &on_chunk)
      check_run_arguments(mode: mode, offset: offset, chunk_size: chunk_size)
      check_mapped_columns(mapped_columns: mapped_columns)

      RunProcessor.call(
        source_reader: @source_reader, resolved_mapped_columns: resolve_mapped_columns(mapped_columns: mapped_columns),
        offset: offset, chunk_size: chunk_size, mode: mode, target: target, &on_chunk
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
      columns_by_name = {}
      target_schema.columns.each { |target_column| columns_by_name[target_column.name] = target_column }

      columns_by_name
    end

    # Stops with every mistake in the mapped columns, or does nothing when there is none.
    def check_mapped_columns(mapped_columns:)
      MappedDataValidator.new(
        source_header_names: @source_reader.headers,
        target_column_names: target_columns_by_name.keys,
        required_target_column_names: target_schema.columns.select(&:required).map(&:name),
        target_table_name: target_schema.table_name
      ).call(mapped_columns: mapped_columns)
    end

    # The target of the target model, which reads its schema, casts texts and builds records.
    def target
      if @target.nil?
        # Kept only once the target is built, so a failed build is tried again on the next call.
        @target = self.class.target_class.new(target_model_name: @target_model_name)
      end

      @target
    end

    # The schema of the target table. The target is asked on the first call and the answer is
    # kept. A failed read is not kept, so the next call asks again.
    def target_schema
      if @target_schema.nil?
        @target_schema = target.schema
      end

      @target_schema
    end

    # Makes the resolved mapped columns that the column values stage and the run take from the consumer's mapped
    # columns, which the engine has checked: each entry gets the column of the target table it fills.
    #
    # @param mapped_columns [Hash{String => Hash}] target column => the entry the caller wrote
    # @return [Hash{String => ResolvedMappedColumn}] the same keys; the caller's entries are not changed
    def resolve_mapped_columns(mapped_columns:)
      columns_by_name = target_columns_by_name
      resolved_mapped_columns = {}

      mapped_columns.each do |target_column_name, entry|
        target_column = columns_by_name.fetch(target_column_name)
        resolved_mapped_columns[target_column_name] = ResolvedMappedColumn.from_entry(
          entry: entry, target_column: target_column
        )
      end

      resolved_mapped_columns
    end
  end
end
