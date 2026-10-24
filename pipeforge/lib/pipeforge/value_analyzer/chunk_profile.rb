# frozen_string_literal: true

require_relative "distinct_values"

module Pipeforge
  module ValueAnalyzer
    # What the scan found out about one mapped target column. A ChunkProfile or a Result holds it
    # under the name of the target column.
    #   source_column       the source column it is read from
    #   position            the position of the source column in the file, starting at 1
    #   empty               how many cells are empty
    #   type_compatibility  {fits:, total:}: how many of the non-empty values fit the target type
    #   distinct_values     {compatible:, incompatible:}, each a DistinctValues
    #   value_mapping       the consumer's mapping of source values to the values to load; the
    #                       counts and the lists above describe the values after applying it,
    #                       that is, what would be loaded
    ColumnSummary = Data.define(
      :source_column, :position, :empty, :type_compatibility, :distinct_values, :value_mapping
    ) do
      # A column with nothing counted yet.
      #
      # @param source_column [String] the source column it is read from
      # @param position [Integer] the position of the source column in the file, starting at 1
      # @param value_mapping [Hash] the consumer's mapping of source values to the values to load
      # @param cap [Integer, nil] how many different values each list keeps; nil keeps every value
      # @return [ColumnSummary]
      def self.empty(source_column:, position:, value_mapping:, cap:)
        new(
          source_column: source_column,
          position: position,
          empty: 0,
          type_compatibility: {fits: 0, total: 0},
          distinct_values: {
            compatible: DistinctValues.new(cap: cap),
            incompatible: DistinctValues.new(cap: cap)
          },
          value_mapping: value_mapping
        )
      end

      # Adds the summary of a later part of the file to this one: the numbers are added and the
      # distinct values are merged. The source column, the position and the value mapping stay those
      # of this summary.
      #
      # @param later [ColumnSummary] the same column, measured on rows after this summary's rows
      # @return [ColumnSummary] a new summary; neither input changes
      def merge(later:)
        with(
          empty: empty + later.empty,
          type_compatibility: {
            fits: type_compatibility[:fits] + later.type_compatibility[:fits],
            total: type_compatibility[:total] + later.type_compatibility[:total]
          },
          distinct_values: {
            compatible: distinct_values[:compatible].merge(later: later.distinct_values[:compatible]),
            incompatible: distinct_values[:incompatible].merge(later: later.distinct_values[:incompatible])
          }
        )
      end

      # @return [Hash] plain JSON types, with each list as an array of {value:, count:}
      def to_h
        {
          source_column: source_column,
          position: position,
          empty: empty,
          type_compatibility: type_compatibility,
          distinct_values: {
            compatible: distinct_values[:compatible].values,
            incompatible: distinct_values[:incompatible].values
          },
          value_mapping: value_mapping
        }
      end
    end

    # The partial result of analysing one chunk or, after merging, any number of chunks: the
    # ColumnSummary of every mapped column, by target column name. Every profile holds the same
    # columns, so two profiles can always be merged.
    ChunkProfile = Data.define(:columns) do
      # A profile with an empty summary for each target column.
      #
      # @param mapped_columns [Hash{String => Hash}] target column => {source_column:, position:,
      #   value_mapping:, ...}, as {ChunkAnalyzer} takes them; the other keys are ignored
      # @param cap [Integer, nil] how many different values each list keeps; nil keeps every
      #   value. A profile that chunks are merged into has the cap, so the values of the first
      #   chunk are capped too.
      # @return [ChunkProfile]
      def self.empty(mapped_columns:, cap:)
        column_summaries = {}

        mapped_columns.each do |target_column, mapped_column|
          column_summaries[target_column] = ColumnSummary.empty(
            source_column: mapped_column[:source_column],
            position: mapped_column[:position],
            value_mapping: mapped_column.fetch(:value_mapping, {}),
            cap: cap
          )
        end

        new(columns: column_summaries)
      end

      # @param later [ChunkProfile] the profile of rows that come after this one's rows
      # @return [ChunkProfile] a new profile; neither input changes
      def merge(later:)
        merged_columns = {}

        columns.each do |target_column, earlier_summary|
          merged_columns[target_column] = earlier_summary.merge(later: later.columns.fetch(target_column))
        end

        with(columns: merged_columns)
      end
    end
  end
end
