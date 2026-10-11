# frozen_string_literal: true

module Pipeforge
  class ValueAnalyzer
    # Measures one chunk of rows into a ChunkProfile: for each mapped column, how many values
    # are empty, how many fit the target type, and the distinct values that do and do not fit.
    #
    # It is a pure function of its rows: the same rows give the same profile and nothing is
    # kept between chunks. The rows are data rows (the reader drops blank ones) and an empty
    # value is nil.
    #
    # Only the mapped columns are measured. Every one of them is in the result, with zero
    # counts when no row had it, so any two profiles can be merged. The lists of one chunk are
    # not capped, because a chunk holds a bounded number of rows; the cap applies when profiles
    # are merged, so a value that is listed is counted in every chunk.
    class ChunkAnalyzer
      # @param config [Configuration] +source.distinct_values_cap+ is the list cap
      # @param checkers [Hash{String => TypeChecker}] one per mapped source column
      def initialize(config:, checkers:)
        @checkers = checkers
        @distinct_values_cap = config.source.distinct_values_cap
      end

      # The profile with every mapped column and nothing counted yet, where merging starts.
      # It carries the cap, so the cap applies to every value merged into it.
      #
      # @return [ChunkProfile]
      def empty_profile
        ChunkProfile.empty(source_columns: @checkers.keys, cap: @distinct_values_cap)
      end

      # @param rows [Array<Hash{String => String, nil}>] one chunk, as the reader yields it
      # @return [ChunkProfile] the measurements of this chunk alone
      def call(rows:)
        column_summaries = {}

        count_values(rows: rows).each do |source_column, counts|
          column_summaries[source_column] = summarize(checker: @checkers[source_column], counts: counts)
        end

        ChunkProfile.new(columns: column_summaries)
      end

      private

      # For every mapped source column: {empty:, values: {text => how many times}}, the values
      # in the order they first appear.
      def count_values(rows:)
        column_counts = {}

        @checkers.each_key do |source_column|
          column_counts[source_column] = {empty: 0, values: {}}
        end

        rows.each do |row|
          row.each do |source_column, value|
            next unless @checkers.key?(source_column)

            counts = column_counts[source_column]

            if value.nil?
              counts[:empty] += 1
            elsif counts[:values].key?(value)
              counts[:values][value] += 1
            else
              counts[:values][value] = 1
            end
          end
        end

        column_counts
      end

      # Each distinct value is checked once and counted as many times as it appeared. The target
      # column and the position are filled in when the scan is finished.
      def summarize(checker:, counts:)
        fits = 0
        total = 0
        compatible = DistinctValues.new(cap: nil)
        incompatible = DistinctValues.new(cap: nil)

        counts[:values].each do |value, count|
          total += count

          if checker.fits?(text: value)
            fits += count
            compatible.record(value: value, count: count)
          else
            incompatible.record(value: value, count: count)
          end
        end

        ColumnSummary.new(
          target_column: nil,
          position: nil,
          empty: counts[:empty],
          type_compatibility: {fits: fits, total: total},
          distinct_values: {compatible: compatible, incompatible: incompatible}
        )
      end
    end
  end
end
