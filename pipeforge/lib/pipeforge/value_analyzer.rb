# frozen_string_literal: true

require "json"
require_relative "fingerprint"
require_relative "value_analyzer/type_checker"
require_relative "value_analyzer/chunk_profile"
require_relative "source/csv_reader"
require_relative "value_analyzer/chunk_analyzer"

module Pipeforge
  # Measures the mapped columns of a CSV source: for each one, how many values are empty, how
  # many fit the type of its target column, and which distinct values do and do not fit.
  #
  # It is a service: {.call} is given everything it needs and does the whole job, once. It
  # keeps nothing between calls, so any number of engines can use it at the same time.
  #
  # The file is read once, in chunks, so memory stays bounded. Each chunk is measured on its
  # own and the partial results are merged in file order, which makes the result independent
  # of the chunk size. The analyzer reads source values only and never touches the target.
  #
  # @example
  #   mapping = {"Mail" => {target_column: "email", type: "string", max_length: 255}}
  #   result = Pipeforge::ValueAnalyzer.call(source_reader: source_reader, mapped_columns: mapping)
  #   result.columns["Mail"].type_compatibility # => {fits: 1170, total: 1188}
  module ValueAnalyzer
    # The outcome of one analysis.
    #   source_identifier  the file path of the source, or its class name when it has no path
    #   row_count          data rows read; blank and all-empty rows are not counted
    #   columns            a ColumnSummary per mapped source column, keyed by its header and
    #                      in the order of the columns in the file
    #   source_fingerprint the fingerprint of the parsed rows (see {Fingerprint}), or nil when
    #                      the source fingerprint setting is off
    Result = Data.define(:source_identifier, :row_count, :columns, :source_fingerprint) do
      # @return [Hash] the result as plain JSON types, ready to store or send
      def to_h
        columns_as_hashes = {}

        columns.each do |source_column, column_summary|
          columns_as_hashes[source_column] = column_summary.to_h
        end

        {
          source_identifier: source_identifier,
          row_count: row_count,
          source_fingerprint: source_fingerprint,
          columns: columns_as_hashes
        }
      end
    end

    class << self
      # Reads the file and measures every mapped column.
      #
      # A mapped column may carry a +value_mapping+. Each of its values is then measured as the
      # value it maps to, which is what would be loaded, and the mapping comes back in the result
      # so it can be edited and passed in again.
      #
      # The mapped columns are trusted: the engine checks them against the file header and the
      # target schema (MappedDataValidator) before this is called. The header is checked by the
      # reader before any row is read. A file with no data rows is not an error: its mapped
      # columns come back with zero counts.
      #
      # @param source_reader [Source::CsvReader] the reader of the CSV source
      # @param mapped_columns [Hash{String => Hash}] source column => {target_column:, type:, ...,
      #   value_mapping: {value in the file => value to load}}. Only these columns are measured.
      #   +value_mapping+ is optional, and a value that maps to nil or a blank is loaded as empty.
      #   The type keys are described in {TypeChecker}.
      # @return [Result]
      # @raise [Source::EmptySourceError] the file has no header line
      # @raise [Source::InvalidHeaderError] a header cell is blank or a name appears twice
      # @raise [Source::MalformedSourceError] a row cannot be parsed
      def call(source_reader:, mapped_columns:)
        column_rules = build_column_rules(mapped_columns: mapped_columns)
        profile = ChunkProfile.empty(
          source_columns: column_rules.keys, cap: Configuration.source.distinct_values_cap
        )
        fingerprint = Configuration.source.fingerprint ? Fingerprint.new : nil

        row_count = source_reader.each_chunk do |rows|
          add_rows_to_fingerprint(fingerprint: fingerprint, rows: rows) if fingerprint
          profile = profile.merge(later: ChunkAnalyzer.call(rows: rows, column_rules: column_rules))
        end

        build_result(
          source_reader: source_reader,
          mapped_columns: mapped_columns,
          profile: profile,
          row_count: row_count,
          source_fingerprint: fingerprint&.value
        )
      end

      private

      # The type checker and the value mapping of each mapped source column; the value mapping is
      # {} when the column has none.
      def build_column_rules(mapped_columns:)
        column_rules = {}

        mapped_columns.each do |source_column, column_info|
          column_rules[source_column] = {
            type_checker: TypeChecker.new(type_info: column_info),
            value_mapping: column_info.fetch(:value_mapping, {})
          }
        end

        column_rules
      end

      # Adds each row to the fingerprint as one line: its values as a JSON array, in header order.
      # JSON keeps the values apart (a comma inside a value is not a separator) and writes an
      # empty cell as null.
      def add_rows_to_fingerprint(fingerprint:, rows:)
        rows.each do |row|
          fingerprint.add(text: "#{JSON.generate(row.values)}\n")
        end
      end

      # Follows the header, so the result is in file order whatever the order of the mapping.
      def build_result(source_reader:, mapped_columns:, profile:, row_count:, source_fingerprint:)
        columns = {}

        source_reader.headers.each_with_index do |source_column, index|
          next unless mapped_columns.key?(source_column)

          column_info = mapped_columns[source_column]

          columns[source_column] = profile.columns[source_column].with(
            target_column: column_info[:target_column],
            position: index + 1,
            value_mapping: column_info.fetch(:value_mapping, {})
          )
        end

        Result.new(
          source_identifier: source_reader.identifier,
          row_count: row_count,
          columns: columns,
          source_fingerprint: source_fingerprint
        )
      end
    end
  end
end
