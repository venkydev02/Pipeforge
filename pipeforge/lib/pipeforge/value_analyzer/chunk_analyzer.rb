# frozen_string_literal: true

module Pipeforge
  module ValueAnalyzer
    # Measures one chunk of rows into a ChunkProfile: for each mapped column, how many values
    # are empty, how many fit the target type, and the distinct values that do and do not fit.
    #
    # It is a service: {.call} is a pure function of its rows and mapped columns, so the same rows
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
    # +mapped_columns+ is a Hash{String => Hash}: one entry per mapped target column, as the value
    # analyzer prepares it. The entry says what its values are read from and measured by:
    # +source_column+ (the column of the rows the values are read from), +position+ (of that
    # column in the file), +type_checker+ (the {TypeChecker} of the target column, which decides
    # whether a value fits), and optionally +value_mapping+ ({value in the file => value to
    # load}).
    # Several target columns may read the same source column; each is measured on its own.
    module ChunkAnalyzer
      class << self
        # @param rows [Array<Hash{String => String, nil}>] one chunk, as the reader yields it
        # @param mapped_columns [Hash{String => Hash}] see the module description
        # @return [ChunkProfile] the measurements of this chunk alone
        def call(rows:, mapped_columns:)
          column_summaries = {}

          count_values(rows: rows, mapped_columns: mapped_columns).each do |target_column, column_cells|
            column_summaries[target_column] = summarize(
              mapped_column: mapped_columns[target_column],
              column_cells: column_cells
            )
          end

          ChunkProfile.new(columns: column_summaries)
        end

        private

        # For every mapped target column: {empty:, values:}, where +values+ is a DistinctValues
        # that holds each value of the column with how many times it appeared, in the order the
        # values first appear. It has no cap: the cap applies when profiles are merged.
        def count_values(rows:, mapped_columns:)
          column_counts = {}

          mapped_columns.each do |target_column, mapped_column|
            column_cells = {empty: 0, values: DistinctValues.new(cap: nil)}

            rows.each do |row|
              value = row[mapped_column[:source_column]]

              if value.nil?
                column_cells[:empty] += 1
              else
                column_cells[:values].record(value: value)
              end
            end

            column_counts[target_column] = column_cells
          end

          column_counts
        end

        # Each distinct value is checked once, as the value it maps to, and counted as many times
        # as it appeared; the lists hold the value that would be loaded.
        #
        # +mapped_column+ here is the entry of one column.
        def summarize(mapped_column:, column_cells:)
          type_checker = mapped_column.fetch(:type_checker)
          value_mapping = mapped_column.fetch(:value_mapping, {})
          empty = column_cells[:empty]
          fits = 0
          total = 0
          compatible = DistinctValues.new(cap: nil)
          incompatible = DistinctValues.new(cap: nil)

          column_cells[:values].value_counts.each do |value, count|
            loaded_value = value_mapping.fetch(value, value)

            if Utilities.blank?(value: loaded_value)
              empty += count
              next
            end

            total += count
            loaded_text = loaded_value.to_s

            if type_checker.fits?(text: loaded_text)
              fits += count
              compatible.record(value: loaded_text, count: count)
            else
              incompatible.record(value: loaded_text, count: count)
            end
          end

          ColumnSummary.new(
            source_column: mapped_column[:source_column],
            position: mapped_column[:position],
            empty: empty,
            type_compatibility: {fits: fits, total: total},
            distinct_values: {compatible: compatible, incompatible: incompatible},
            value_mapping: value_mapping
          )
        end
      end
    end
  end
end
