# frozen_string_literal: true

require_relative "source/reusable_io"
require_relative "source/csv_reader"
require_relative "value_analyzer"
require_relative "header_analyzer"
require_relative "target_schema"
require_relative "target_adapter"
require_relative "mapped_data_validator"

module Pipeforge
  # The entry point of the engine. It is given the source once, checks it, and hands the work
  # to the stages, so the caller does not repeat it for each action. The settings are not its
  # concern: each part reads the ones it needs from {Configuration}.
  #
  # @example
  #   engine = Pipeforge::Engine.new(source_io: File.open("data/users.csv"), target_table: "users")
  #   header_analysis = engine.analyze_headers
  #   value_analysis = engine.analyze_values(
  #     mapped_columns: {"Mail" => {target_column: "email", value_mapping: {"N/A" => nil}}}
  #   )
  class Engine
    # @param source_io [IO] the CSV source, for example +File.open("data/users.csv")+. It must
    #   respond to +read+, +rewind+ and +seek+. The engine wraps it in a {Source::ReusableIO}, which
    #   is rewound before each read, so the same object can be used again.
    # @param target_table [String] the table the data will be loaded into. Every stage works on
    #   this table, and the engine reads its schema (the types of its columns) itself.
    # The target adapter is not an argument: an adapter gem installs it in {TargetAdapter} when it
    # is loaded (ADR-16), and the engine cannot be built without one.
    #
    # @raise [TargetAdapterError] no adapter gem is loaded (+target_adapter_not_installed+)
    # @raise [Source::UnsupportedSourceError] the source is missing a method the engine needs
    def initialize(source_io:, target_table:)
      TargetAdapter.ensure_installed
      @source_reader = Source::CsvReader.new(source_io: Source::ReusableIO.new(io: source_io))
      @target_table = target_table
    end

    # Matches the columns of the source to the columns of the target table by name only, and
    # returns the best matches, keyed by target column, with the metadata of each target column,
    # and the columns left unmatched (the header stage, ADR-14). Only the header of the source
    # and the schema of the target are read, never any value or row.
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
    # the type of the target column, and which distinct values do and do not fit. The type,
    # size and precision of each target column come from the schema of the target table (ADR-18),
    # never from the caller.
    #
    # Call it again after editing a value mapping to see the facts again: with a value mapping,
    # each value is measured as the value it maps to, so the counts show what would be loaded,
    # and the mapping comes back in the result to be edited once more. The rows are read again
    # each time, so an edited mapping is picked up; the source is not expected to change while
    # the engine exists.
    #
    # @param mapped_columns [Hash{String => Hash}] source column => {target_column:,
    #   value_mapping: {value in the file => value to load}}. +value_mapping+ is optional, its keys
    #   are turned into text (the values of the file are text, so +1+ and +"1"+ are the same key),
    #   and a value that maps to nil or a blank is loaded as empty. The entries must not be frozen:
    #   the type metadata of each target column is added to them (see {#add_type_metadata})
    #   and the keys of their value mapping are replaced by text.
    # @return [ValueAnalyzer::Result]
    # @raise [TargetSchemaError] the table or its model cannot be found
    # @raise [Source::EmptySourceError] the source has no header row
    # @raise [Source::InvalidHeaderError] a header cell is blank or a name appears twice
    # @raise [InvalidMappedColumnsError] a mapped column is not in the file, has no target column
    #   or a target column that is not in the schema; every such mistake is listed
    # @raise [Source::MalformedSourceError] a row cannot be parsed
    def analyze_values(mapped_columns:)
      target_columns = {}
      target_schema.columns.each { |target_column| target_columns[target_column.name] = target_column }

      MappedDataValidator.new(
        source_header_names: @source_reader.headers,
        target_column_names: target_columns.keys,
        target_table: @target_table
      ).call(mapped_columns: mapped_columns)

      add_type_metadata(mapped_columns: mapped_columns, target_columns: target_columns)
      convert_value_mapping_keys(mapped_columns: mapped_columns)

      ValueAnalyzer.call(source_reader: @source_reader, mapped_columns: mapped_columns)
    end

    private

    # The schema of the target table. The adapter is asked once and the answer is kept, like the
    # header of the source: an engine is built for one source and one table, and neither is
    # expected to change during its life. A failed read is not kept, so the next call asks again.
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

    # Adds the type metadata of the target column (its type, limit, length, precision and scale),
    # taken from the schema, to each entry of the mapped columns, which is how the value stage
    # reads them. It changes the entries it is given: a +type+ the caller sent is replaced by
    # the type of the schema.
    def add_type_metadata(mapped_columns:, target_columns:)
      mapped_columns.each_value do |mapped_column|
        target_column = target_columns.fetch(mapped_column[:target_column])

        mapped_column.merge!(
          type: target_column.type,
          limit: target_column.limit,
          max_length: target_column.max_length,
          precision: target_column.precision,
          scale: target_column.scale
        )
      end
    end
  end
end
