# frozen_string_literal: true

require_relative "value_analyzer/type_checker"
require_relative "value_analyzer/chunk_profile"
require_relative "source/csv_reader"
require_relative "value_analyzer/chunk_analyzer"

module Pipeforge
  # Measures the mapped columns of a CSV source: for each one, how many values are empty, how
  # many fit the type of its target column, and which distinct values do and do not fit.
  #
  # It is a service class: everything it needs is given when it is created, and {#call} does
  # the whole job, once.
  #
  # The file is read once, in chunks, so memory stays bounded. Each chunk is measured on its
  # own and the partial results are merged in file order, which makes the result independent
  # of the chunk size. The analyzer reads source values only and never touches the target.
  #
  # @example
  #   mapping = {"Mail" => {target_column: "email", type: "string", max_length: 255}}
  #   analyzer = Pipeforge::ValueAnalyzer.new(config: config, source_io: File.open("data/users.csv"), mapped_columns: mapping)
  #   result = analyzer.call
  #   result.columns["Mail"].type_compatibility # => {fits: 1170, total: 1188}
  class ValueAnalyzer
    # The outcome of one analysis.
    #   source_identifier  the file path of the source, or its class name when it has no path
    #   row_count          data rows read; blank and all-empty rows are not counted
    #   columns            a ColumnSummary per mapped source column, keyed by its header and
    #                      in the order of the columns in the file
    Result = Data.define(:source_identifier, :row_count, :columns) do
      # @return [Hash] the result as plain JSON types, ready to store or send
      def to_h
        columns_as_hashes = {}

        columns.each do |source_column, column_summary|
          columns_as_hashes[source_column] = column_summary.to_h
        end

        {source_identifier: source_identifier, row_count: row_count, columns: columns_as_hashes}
      end
    end

    # A mapped column may carry a +value_mapping+. Each of its values is then measured as the
    # value it maps to, which is what would be loaded, and the mapping comes back in the result
    # so it can be edited and passed in again.
    #
    # The mapped columns are trusted to be complete: the engine checks them before this is
    # created.
    #
    # @param config [Configuration] the engine settings (chunk size and distinct values cap)
    # @param source_io [IO] the CSV source; it must respond to +read+, +rewind+ and +seek+
    # @param mapped_columns [Hash{String => Hash}] source column => {target_column:, type:, ...,
    #   value_mapping: {value in the file => value to load}}. Only these columns are measured.
    #   +value_mapping+ is optional, and a value that maps to nil or a blank is loaded as empty.
    #   The type keys are described in {TypeChecker}.
    def initialize(config:, source_io:, mapped_columns:)
      @config = config
      @source_io = source_io
      @mapped_columns = mapped_columns
    end

    # Reads the file and measures every mapped column.
    #
    # The header is trusted to be usable (the header stage checks the file itself). A file with
    # no data rows is not an error: its mapped columns come back with zero counts.
    #
    # @return [Result]
    # @raise [Source::MissingColumnError] a mapped source column is not in the file header
    # @raise [Source::MalformedSourceError] a row cannot be parsed
    def call
      type_checkers = build_type_checkers
      reader = Source::CsvReader.new(source_io: @source_io, config: @config)
      chunk_analyzer = ChunkAnalyzer.new(
        config: @config, type_checkers: type_checkers, value_mappings: build_value_mappings
      )
      profile = chunk_analyzer.empty_profile
      header_checked = false

      reader.each_chunk do |rows|
        unless header_checked
          # Every row carries every column, so the first row shows the whole header.
          reject_missing_columns(header_names: rows.first.keys)
          header_checked = true
        end

        profile = profile.merge(later: chunk_analyzer.call(rows: rows))
      end

      # A file with no data rows has no chunk, so its header is checked here.
      reject_missing_columns(header_names: reader.headers) unless header_checked

      build_result(reader: reader, profile: profile)
    end

    private

    # One TypeChecker per mapped source column.
    def build_type_checkers
      type_checkers = {}

      @mapped_columns.each do |source_column, column_info|
        type_checkers[source_column] = TypeChecker.new(type_info: column_info)
      end

      type_checkers
    end

    # The value mapping of each mapped source column; {} when it has none.
    def build_value_mappings
      value_mappings = {}

      @mapped_columns.each do |source_column, column_info|
        value_mappings[source_column] = column_info.fetch(:value_mapping, {})
      end

      value_mappings
    end

    # Raises Source::MissingColumnError, naming every mapped column the header does not have.
    def reject_missing_columns(header_names:)
      missing = @mapped_columns.keys - header_names
      return if missing.empty?

      errors = missing.map do |source_column|
        {
          code: :mapped_column_not_in_file,
          message: "mapped source column #{source_column} is not in the file",
          source_column: source_column
        }
      end

      raise Source::MissingColumnError.new(
        message: "mapped source columns not found in the file: #{missing.join(", ")}", errors: errors
      )
    end

    # Follows the header, so the result is in file order whatever the order of the mapping.
    def build_result(reader:, profile:)
      columns = {}

      reader.headers.each_with_index do |source_column, index|
        next unless @mapped_columns.key?(source_column)

        column_info = @mapped_columns[source_column]

        columns[source_column] = profile.columns[source_column].with(
          target_column: column_info[:target_column],
          position: index + 1,
          value_mapping: column_info.fetch(:value_mapping, {})
        )
      end

      Result.new(source_identifier: source_identifier, row_count: reader.row_count, columns: columns)
    end

    # The file path of the source when it has one, else the name of its class.
    def source_identifier
      return @source_io.path.to_s if @source_io.respond_to?(:path)

      @source_io.class.name
    end
  end
end
