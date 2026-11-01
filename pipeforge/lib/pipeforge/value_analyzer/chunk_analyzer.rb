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
    # column in the file), +limits_checker+ (the {ColumnLimitsChecker} of the target column), and
    # optionally +value_mapping+ ({value in the file => value to load}).
    #
    # A value fits when the adapter can read it (it casts it to something other than nil) and the cast
    # value is within the limits of the column. Every type is cast, including a type the core knows no
    # limit for. A value is also given as +casted_to+ when the cast value, written as text, is not the
    # value itself (+abc+ in an integer column is +"0"+), whether it fits or not.
    # Several target columns may read the same source column; each is measured on its own.
    module ChunkAnalyzer
      class << self
        # @param rows [Array<Hash{String => String, nil}>] one chunk, as the reader yields it
        # @param mapped_columns [Hash{String => Hash}] see the module description
        # @param model_adapter [#cast_text] the adapter's object for the target table, which casts a text
        #   for a column
        # @return [ChunkProfile] the measurements of this chunk alone
        def call(rows:, mapped_columns:, model_adapter:)
          column_summaries = {}

          count_values(rows: rows, mapped_columns: mapped_columns).each do |target_column, column_cells|
            column_summaries[target_column] = summarize(
              target_column: target_column,
              mapped_column: mapped_columns[target_column],
              column_cells: column_cells,
              model_adapter: model_adapter
            )
          end

          ChunkProfile.new(columns: column_summaries)
        end

        private

        # For every mapped target column: {empty:, values:}, where +values+ is a Hash of each value of the
        # column with how many times it appeared, in the order the values first appear.
        def count_values(rows:, mapped_columns:)
          column_counts = {}

          mapped_columns.each do |target_column, mapped_column|
            column_cells = {empty: 0, values: Hash.new(0)}

            rows.each do |row|
              value = row[mapped_column[:source_column]]

              if value.nil?
                column_cells[:empty] += 1
              else
                column_cells[:values][value] += 1
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
        def summarize(target_column:, mapped_column:, column_cells:, model_adapter:)
          limits_checker = mapped_column.fetch(:limits_checker)
          value_mapping = mapped_column.fetch(:value_mapping, {})
          empty = column_cells[:empty]
          fits = 0
          total = 0
          # No cap here: the cap applies when the profiles are merged.
          compatible = DistinctValues.new(cap: nil)
          incompatible = DistinctValues.new(cap: nil)

          column_cells[:values].each do |value, count|
            loaded_value = value_mapping.fetch(value, value)

            if Utilities.blank?(value: loaded_value)
              empty += count
              next
            end

            total += count
            loaded_text = loaded_value.to_s

            fits_the_column, casted_to = check_text(
              text: loaded_text, target_column: target_column, limits_checker: limits_checker, model_adapter: model_adapter
            )

            if fits_the_column
              fits += count
              compatible.record(value: loaded_text, count: count, casted_to: casted_to)
            else
              incompatible.record(value: loaded_text, count: count, casted_to: casted_to)
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

        # Whether a text fits the column, and what it is changed to. The adapter casts the text, whatever
        # the type of the column; a nil cast means it cannot read it, so it does not fit and there is no
        # changed value; otherwise the cast value must be within the limits of the column, when the type
        # has any. The changed value is given whether or not the text fits.
        #
        # @return [Array(Boolean, String)] whether it fits, and the changed value (nil when none)
        def check_text(text:, target_column:, limits_checker:, model_adapter:)
          cast_value = model_adapter.cast_text(column_name: target_column, text: text)
          return [false, nil] if cast_value.nil?

          # The changed value is given even when the text does not fit, because the cast value can be the
          # reason: 999.999 is cast to 1000.0 in a decimal column of scale 2.
          [limits_checker.violation_of(value: cast_value).nil?, casted_to(text: text, cast_value: cast_value)]
        end

        # The cast value written as text, when it differs from the text: +abc+ in an integer column is
        # +"0"+, +1,000+ is +"1"+, +2024-2-3+ in a date column is +"2024-02-03"+, and +no+ in a boolean
        # column is +"true"+. A form that only writes the same value differently also differs (+10.50+ is
        # +"10.5"+, a timestamp gains the +T+ and the zone).
        # A value that is not a string, a number, a boolean, a date or a time (an array, a range) is not
        # written as text, so it is never given.
        def casted_to(text:, cast_value:)
          return nil unless writable_as_text?(cast_value: cast_value)

          cast_text = written_as_text(cast_value: cast_value)

          (cast_text == text) ? nil : cast_text
        end

        def writable_as_text?(cast_value:)
          cast_value.is_a?(String) || cast_value.is_a?(Numeric) || [true, false].include?(cast_value) ||
            cast_value.respond_to?(:iso8601)
        end

        # A date or a time in ISO 8601, a decimal in plain notation, anything else as its own text.
        def written_as_text(cast_value:)
          return cast_value.iso8601 if cast_value.respond_to?(:iso8601)
          # Only a BigDecimal answers exponent; to_d would also match an Integer or a Float once ActiveSupport
          # is loaded, and their to_s takes no format.
          return cast_value.to_s("F") if cast_value.respond_to?(:exponent)

          cast_value.to_s
        end
      end
    end
  end
end
