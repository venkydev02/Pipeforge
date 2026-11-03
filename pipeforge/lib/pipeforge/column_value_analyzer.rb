# frozen_string_literal: true

require_relative "column_limits_checker"
require_relative "column_value_analyzer/column_summary_builder"
require_relative "source/csv_reader"

module Pipeforge
  # Measures the mapped columns of a CSV source: for each one, how many values are empty, how
  # many fit the type of its target column, and which distinct values do and do not fit.
  #
  # It is a service: {.call} is given everything it needs and does the whole job, once. It
  # keeps nothing between calls, so any number of engines can use it at the same time.
  #
  # The file is read once, one row at a time, and each value is added to the summary builder of
  # its column. Every distinct value of every mapped column is kept, because the result is
  # complete only after the last row, so memory grows with the number of distinct values. The
  # analyzer reads source values only and never touches the target.
  #
  # The {Engine} is the way in: {Engine#analyze_column_values} checks the mapped columns, adds the type
  # metadata of the target columns and then calls this service.
  #
  # @api private
  #
  # @example through the engine
  #   result = engine.analyze_column_values(mapped_columns: {"email" => {source_column: "Mail"}})
  #   result.columns["email"].type_compatibility # => {fits: 1170, total: 1188}
  module ColumnValueAnalyzer
    # The outcome of one analysis.
    #   source_identifier  the file path of the source, or its class name when it has no path
    #   row_count          data rows read; blank and all-empty rows are not counted
    #   columns            a ColumnSummary per mapped target column, keyed by the target column
    #                      and in the order of the mapped columns
    Result = Data.define(:source_identifier, :row_count, :columns) do
      # @return [Hash] the result as plain JSON types, ready to store or send
      def to_h
        columns_as_hashes = {}

        columns.each do |target_column, column_summary|
          columns_as_hashes[target_column] = column_summary.to_h
        end

        {
          source_identifier: source_identifier,
          row_count: row_count,
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
      # the {ColumnLimitsChecker} of each target column are added to the entries. A file with no data
      # rows is not an error: its mapped columns come back with zero counts. A source column
      # mapped to several target columns is measured once for each of them.
      #
      # @param source_reader [Source::CsvReader] the reader of the CSV source
      # @param model_adapter [#cast_text] the adapter's object for the target table, which casts a text
      #   for a column so that it is checked as the value it would load
      # @param mapped_columns [Hash{String => Hash}] target column => {source_column:, type:, ...,
      #   value_mapping: {value in the file => value to load}}. Only these columns are measured.
      #   +value_mapping+ is optional, its keys are text (the values of the file are text), and a
      #   value that maps to nil or a blank is loaded as empty.
      #   The type keys are described in {ColumnLimitsChecker}.
      # @return [Result]
      # @raise [Source::EmptySourceError] the file has no header line
      # @raise [Source::InvalidHeaderError] a header cell is blank or a name appears twice
      # @raise [Source::MalformedSourceError] a row cannot be parsed
      def call(source_reader:, mapped_columns:, model_adapter:)
        add_positions(mapped_columns: mapped_columns, header_names: source_reader.headers)
        add_limits_checkers(mapped_columns: mapped_columns)

        summary_builders = {}
        mapped_columns.each do |target_column, mapped_column|
          summary_builders[target_column] = ColumnSummaryBuilder.new(
            target_column: target_column, mapped_column: mapped_column, model_adapter: model_adapter
          )
        end

        row_count = source_reader.each_row do |row|
          summary_builders.each_value { |summary_builder| summary_builder.add_row(row: row) }
        end

        column_summaries = {}
        summary_builders.each { |target_column, summary_builder| column_summaries[target_column] = summary_builder.summary }

        Result.new(source_identifier: source_reader.identifier, row_count: row_count, columns: column_summaries)
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

      # Adds the {ColumnLimitsChecker} of the target column, built from the type metadata of the entry, to
      # each entry of the mapped columns. It changes the entries it is given.
      def add_limits_checkers(mapped_columns:)
        mapped_columns.each_value do |mapped_column|
          mapped_column[:limits_checker] = ColumnLimitsChecker.new(type_info: mapped_column)
        end
      end
    end
  end
end
