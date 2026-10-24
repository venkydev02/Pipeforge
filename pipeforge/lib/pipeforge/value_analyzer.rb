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
  # The {Engine} is the way in: {Engine#analyze_values} checks the mapped columns, adds the type
  # metadata of the target columns and then calls this service.
  #
  # @api private
  #
  # @example through the engine
  #   result = engine.analyze_values(mapped_columns: {"email" => {source_column: "Mail"}})
  #   result.columns["email"].type_compatibility # => {fits: 1170, total: 1188}
  module ValueAnalyzer
    # The outcome of one analysis.
    #   source_identifier  the file path of the source, or its class name when it has no path
    #   row_count          data rows read; blank and all-empty rows are not counted
    #   columns            a ColumnSummary per mapped target column, keyed by the target column
    #                      and in the order of the mapped columns
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
      # value it maps to, which is what would be loaded, and the mapping comes back in the result.
      #
      # The mapped columns must already be checked against the file header and the target schema
      # ({MappedDataValidator}) and carry the type metadata of their target column and text keys
      # in their value mapping; the {Engine} does both. The position of each source column and
      # the {TypeChecker} of each target column are added to the entries. A file with no data
      # rows is not an error: its mapped columns come back with zero counts. A source column
      # mapped to several target columns is measured once for each of them.
      #
      # @param source_reader [Source::CsvReader] the reader of the CSV source
      # @param mapped_columns [Hash{String => Hash}] target column => {source_column:, type:, ...,
      #   value_mapping: {value in the file => value to load}}. Only these columns are measured.
      #   +value_mapping+ is optional, its keys are text (the values of the file are text), and a
      #   value that maps to nil or a blank is loaded as empty.
      #   The type keys are described in {TypeChecker}.
      # @return [Result]
      # @raise [Source::EmptySourceError] the file has no header line
      # @raise [Source::InvalidHeaderError] a header cell is blank or a name appears twice
      # @raise [Source::MalformedSourceError] a row cannot be parsed
      def call(source_reader:, mapped_columns:)
        add_positions(mapped_columns: mapped_columns, header_names: source_reader.headers)
        add_type_checkers(mapped_columns: mapped_columns)
        profile = ChunkProfile.empty(mapped_columns: mapped_columns, cap: Configuration.source.distinct_values_cap)
        fingerprint = Configuration.source.fingerprint ? Fingerprint.new : nil

        row_count = source_reader.each_chunk do |rows|
          add_rows_to_fingerprint(fingerprint: fingerprint, rows: rows) if fingerprint
          profile = profile.merge(later: ChunkAnalyzer.call(rows: rows, mapped_columns: mapped_columns))
        end

        Result.new(
          source_identifier: source_reader.identifier,
          row_count: row_count,
          columns: profile.columns,
          source_fingerprint: fingerprint&.value
        )
      end

      private

      # Adds the position of the source column in the file (starting at 1) to each entry of the
      # mapped columns, which is where the summaries read it from. It changes the entries it is
      # given.
      def add_positions(mapped_columns:, header_names:)
        mapped_columns.each_value do |mapped_column|
          mapped_column[:position] = header_names.index(mapped_column[:source_column]) + 1
        end
      end

      # Adds the {TypeChecker} of the target column, built from the type metadata of the entry, to
      # each entry of the mapped columns. It is built once, so every chunk is checked with the
      # same one. It changes the entries it is given.
      def add_type_checkers(mapped_columns:)
        mapped_columns.each_value do |mapped_column|
          mapped_column[:type_checker] = TypeChecker.new(type_info: mapped_column)
        end
      end

      # Adds each row to the fingerprint as one line: its values as a JSON array, in header order.
      # JSON keeps the values apart (a comma inside a value is not a separator) and writes an
      # empty cell as null.
      def add_rows_to_fingerprint(fingerprint:, rows:)
        rows.each do |row|
          fingerprint.add(text: "#{JSON.generate(row.values)}\n")
        end
      end
    end
  end
end
