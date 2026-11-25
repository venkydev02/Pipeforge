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
  # The {Engine} is the way in: {Engine#analyze_column_values} checks the mapped columns, makes a
  # {ResolvedMappedColumn} of each one and then calls this service.
  #
  # @api private
  #
  # @example through the engine
  #   result = engine.analyze_column_values(mapped_columns: {email: {source_column_name: "Mail"}})
  #   result.column_summaries["email"].distinct_values.compatible_count # => 1170
  module ColumnValueAnalyzer
    # The outcome of one analysis.
    #   row_count          data rows read; blank and all-empty rows are not counted
    #   column_summaries   a ColumnSummary per mapped target column, keyed by the target column
    #                      and in the order of the mapped columns
    Result = Data.define(:row_count, :column_summaries) do
      # @return [Hash] the result as plain JSON types, ready to store or send
      def to_h
        column_summaries_as_hashes = {}

        column_summaries.each do |target_column_name, column_summary|
          column_summaries_as_hashes[target_column_name] = column_summary.to_h
        end

        {
          row_count: row_count,
          column_summaries: column_summaries_as_hashes
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
      # ({MappedColumns}); the {Engine} does that. The position of each source column is read from the
      # header, and a {ColumnLimitsChecker} is built for each target column from its type and limits. A file
      # with no data rows is not an error: its mapped columns come back with zero counts. A source column mapped
      # to several target columns is measured once for each of them. Nothing the caller gave is changed.
      #
      # @param source_reader [Source::CsvReader] the reader of the CSV source
      # @param target [#cast_value] the target of the target model, which casts a value
      #   for a column so that it is checked as the value it would load
      # @param resolved_mapped_columns [Hash{String => ResolvedMappedColumn}] target column => its source column, value mapping
      #   and column of the target table, which gives the type and the limits. Only these columns are measured.
      # @return [Result]
      # @raise [Source::Error] the file has no header line, a header cell is blank or a name appears twice, or a row
      #   cannot be parsed or has more cells than the header
      def call(source_reader:, resolved_mapped_columns:, target:)
        header_names = source_reader.headers

        summary_builders = {}
        resolved_mapped_columns.each do |target_column_name, resolved_mapped_column|
          summary_builders[target_column_name] = ColumnSummaryBuilder.new(
            target_column_name: target_column_name,
            source_column_name: resolved_mapped_column.source_column_name,
            position: header_names.index(resolved_mapped_column.source_column_name) + 1,
            limits_checker: ColumnLimitsChecker.for(target_column: resolved_mapped_column.target_column),
            value_mapping: resolved_mapped_column.value_mapping,
            target: target
          )
        end

        row_count = source_reader.each_row do |row|
          summary_builders.each_value do |summary_builder|
            summary_builder.add_cell(cell: row[summary_builder.source_column_name])
          end
        end

        column_summaries = {}
        summary_builders.each { |target_column_name, summary_builder| column_summaries[target_column_name] = summary_builder.summary }

        Result.new(row_count: row_count, column_summaries: column_summaries)
      end
    end
  end
end
