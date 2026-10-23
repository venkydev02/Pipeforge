# frozen_string_literal: true

module Pipeforge
  module ValueAnalyzer
    # Measures one chunk of rows into a ChunkProfile: for each mapped column, how many values
    # are empty, how many fit the target type, and the distinct values that do and do not fit.
    #
    # It is a service: {.call} is a pure function of its rows and column rules, so the same rows
    # give the same profile and nothing is kept between chunks or between calls. The rows are
    # data rows (the reader drops blank ones) and an empty value is nil.
    #
    # Only the mapped columns are measured. Every one of them is in the result, with zero
    # counts when no row had it, so any two profiles can be merged. The lists of one chunk are
    # not capped, because a chunk holds a bounded number of rows; the cap applies when profiles
    # are merged (see {ChunkProfile}), so a value that is listed is counted in every chunk.
    #
    # A value with an entry in the value mapping of its column is measured, and listed, as the
    # value it maps to: that is what would be loaded. Two values that map to the same value are
    # one entry in the lists. A value that maps to nil or to a blank counts as empty and is not
    # listed.
    #
    # +column_rules+ is a Hash{String => Hash} with one entry per mapped source column and what
    # its values are measured by: +type_checker+ (a TypeChecker, which decides
    # whether a value fits the type of the target column) and +value_mapping+ ({value in the
    # file => value to load}, {} when the column has none).
    module ChunkAnalyzer
      class << self
        # @param rows [Array<Hash{String => String, nil}>] one chunk, as the reader yields it
        # @param column_rules [Hash{String => Hash}] see the module description
        # @return [ChunkProfile] the measurements of this chunk alone
        def call(rows:, column_rules:)
          column_summaries = {}

          count_values(rows: rows, column_rules: column_rules).each do |source_column, column_cells|
            column_summaries[source_column] = summarize(
              column_rules: column_rules[source_column],
              column_cells: column_cells
            )
          end

          ChunkProfile.new(columns: column_summaries)
        end

        private

        # For every mapped source column: {empty:, values:}, where +values+ is a DistinctValues
        # that holds each value of the column with how many times it appeared, in the order the
        # values first appear. It has no cap: the cap applies when profiles are merged.
        def count_values(rows:, column_rules:)
          column_counts = {}

          column_rules.each_key do |source_column|
            column_counts[source_column] = {empty: 0, values: DistinctValues.new(cap: nil)}
          end

          rows.each do |row|
            row.each do |source_column, value|
              next unless column_rules.key?(source_column)

              column_cells = column_counts[source_column]

              if value.nil?
                column_cells[:empty] += 1
              else
                column_cells[:values].record(value: value)
              end
            end
          end

          column_counts
        end

        # Each distinct value is checked once, as the value it maps to, and counted as many times
        # as it appeared; the lists hold the value that would be loaded. The target column, the
        # position and the value mapping are filled in when the scan is finished.
        #
        # +column_rules+ here is the entry of one column: its type_checker and value_mapping.
        def summarize(column_rules:, column_cells:)
          empty = column_cells[:empty]
          fits = 0
          total = 0
          compatible = DistinctValues.new(cap: nil)
          incompatible = DistinctValues.new(cap: nil)

          column_cells[:values].value_counts.each do |value, count|
            loaded_value = column_rules[:value_mapping].fetch(value, value)

            if Utilities.blank?(value: loaded_value)
              empty += count
              next
            end

            total += count
            loaded_text = loaded_value.to_s

            if column_rules[:type_checker].fits?(text: loaded_text)
              fits += count
              compatible.record(value: loaded_text, count: count)
            else
              incompatible.record(value: loaded_text, count: count)
            end
          end

          ColumnSummary.new(
            target_column: nil,
            position: nil,
            empty: empty,
            type_compatibility: {fits: fits, total: total},
            distinct_values: {compatible: compatible, incompatible: incompatible},
            value_mapping: {}
          )
        end
      end
    end
  end
end
