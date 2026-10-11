# frozen_string_literal: true

require_relative "value_analyzer/type_checker"
require_relative "value_analyzer/chunk_profile"
require_relative "value_analyzer/chunk_reader"
require_relative "value_analyzer/chunk_analyzer"

module Pipeforge
  # Measures the mapped columns of a CSV source: for each one, how many values are empty, how
  # many fit the type of its target column, and which distinct values do and do not fit.
  #
  # The file is read once, in chunks, so memory stays bounded. Each chunk is measured on its
  # own and the partial results are merged in file order, which makes the result independent
  # of the chunk size. The analyzer reads source values only and never touches the target.
  #
  # @example
  #   mapping = {"Mail" => {target_column: "email", type: "string", max_length: 255}}
  #   analyzer = Pipeforge::ValueAnalyzer.new(config: config)
  #   result = analyzer.call(path: "data/users.csv", column_mapping: mapping)
  #   result.columns["Mail"].type_compatibility # => {fits: 1170, total: 1188}
  class ValueAnalyzer
    # The outcome of one analysis.
    #   source_identifier  the path that was analyzed
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

    # @param config [Configuration] the engine settings (chunk size and distinct values cap)
    def initialize(config:)
      @config = config
    end

    # Reads the file and measures every mapped column.
    #
    # The header is trusted to be usable (the header stage checks the file itself). A file with
    # no data rows is not an error: its mapped columns come back with zero counts.
    #
    # @param path [String] path of a CSV file; streams are not supported
    # @param column_mapping [Hash{String => Hash}] source column => {target_column:, type:, ...}.
    #   Only these columns are measured; the type keys are described in {TypeChecker}.
    # @return [Result]
    # @raise [KeyError] a mapping value has no +target_column+ or no +type+
    # @raise [Source::MissingColumnError] a mapped source column is not in the file header
    # @raise [Source::MalformedSourceError] a row cannot be parsed
    def call(path:, column_mapping:)
      checkers = build_checkers(column_mapping: column_mapping)
      reader = ChunkReader.new(path: path, config: @config)
      chunk_analyzer = ChunkAnalyzer.new(config: @config, checkers: checkers)
      profile = chunk_analyzer.empty_profile
      header_checked = false

      reader.each_chunk do |rows|
        unless header_checked
          # Every row carries every column, so the first row shows the whole header.
          reject_missing_columns(header_names: rows.first.keys, column_mapping: column_mapping)
          header_checked = true
        end

        profile = profile.merge(later: chunk_analyzer.call(rows: rows))
      end

      # A file with no data rows has no chunk, so its header is checked here.
      reject_missing_columns(header_names: reader.headers, column_mapping: column_mapping) unless header_checked

      build_result(path: path, reader: reader, profile: profile, column_mapping: column_mapping)
    end

    private

    # One TypeChecker per mapped source column.
    def build_checkers(column_mapping:)
      checkers = {}

      column_mapping.each do |source_column, target_info|
        raise KeyError, "source column #{source_column} has no target_column" unless target_info.key?(:target_column)

        checkers[source_column] = TypeChecker.new(type_info: target_info)
      end

      checkers
    end

    def reject_missing_columns(header_names:, column_mapping:)
      missing = column_mapping.keys - header_names
      return if missing.empty?

      raise Source::MissingColumnError, "mapped source columns not found in the file: #{missing.join(", ")}"
    end

    # Follows the header, so the result is in file order whatever the order of the mapping.
    def build_result(path:, reader:, profile:, column_mapping:)
      columns = {}

      reader.headers.each_with_index do |source_column, index|
        next unless column_mapping.key?(source_column)

        columns[source_column] = profile.columns[source_column].with(
          target_column: column_mapping[source_column][:target_column],
          position: index + 1
        )
      end

      Result.new(source_identifier: path.to_s, row_count: reader.row_count, columns: columns)
    end
  end
end
