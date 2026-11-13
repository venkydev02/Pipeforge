# frozen_string_literal: true

require_relative "distinct_values"
require_relative "listed_values"

module Pipeforge
  module ColumnValueAnalyzer
    # The distinct texts of one column, split by whether the column accepts them, with how many values each list
    # stands for. Each list holds every different text, most frequent first, and the texts with the same count in
    # the order they first appeared.
    #   compatible          Array<CompatibleValue>    the texts the column accepts
    #   incompatible        Array<IncompatibleValue>  the texts the column does not accept: +reason+ says why,
    #                                                 either +:value_not_castable+ (the adapter could not cast
    #                                                 the text) or the code of the limit the cast value breaks
    #                                                 (+:value_too_long+, +:value_out_of_range+,
    #                                                 +:value_not_allowed+)
    #   compatible_count    Integer                   how many values the column accepts: the sum of the counts
    #                                                 of +compatible+
    #   incompatible_count  Integer                   how many values the column does not accept: the sum of the
    #                                                 counts of +incompatible+
    DistinctValueLists = Data.define(:compatible, :incompatible, :compatible_count, :incompatible_count)

    # What the scan found out about one mapped target column. A Result holds it under the name of the
    # target column.
    #   source_column    String               the source column it is read from
    #   position         Integer              the position of the source column in the file, starting at 1
    #   empty            Integer              how many cells are empty
    #   distinct_values  DistinctValueLists   the texts that fit and the texts that do not, with the number of
    #                                         values in each; the non-empty values are the two counts added up
    #   value_mapping    Hash                 the consumer's mapping of source values to the values to load; the
    #                                         counts and the lists above describe the values after applying it,
    #                                         that is, what would be loaded
    ColumnSummary = Data.define(
      :source_column, :position, :empty, :distinct_values, :value_mapping
    ) do
      # Writes the summary in plain JSON types, to store it.
      #
      # @return [Hash] plain JSON types, with each list as an array of hashes with the fields of its listed values
      def to_h
        {
          source_column: source_column,
          position: position,
          empty: empty,
          distinct_values: {
            compatible: distinct_values.compatible.map(&:to_h),
            incompatible: distinct_values.incompatible.map(&:to_h),
            compatible_count: distinct_values.compatible_count,
            incompatible_count: distinct_values.incompatible_count
          },
          value_mapping: value_mapping
        }
      end
    end

    # The running measurements of one mapped target column while the file is read, one row at a time: how
    # many cells are empty and the distinct values that do and do not fit, each with its number of values. Every
    # distinct value is kept. It is mutable: {#add_cell} is the only method that changes it, and {#summary}
    # gives the finished {ColumnSummary}.
    #
    # A value with an entry in the value mapping of the column is measured as the value it maps to: that is what
    # would be loaded. It is listed under its text from the file, with the value it maps to next to it. A value that
    # maps to nil or to a blank counts as empty and is not listed.
    class ColumnSummaryBuilder
      # @param target_column [String] the target column the values are measured for
      # @param source_column [String] the source column the values are read from
      # @param position [Integer] the position of the source column in the file, starting at 1
      # @param limits_checker [ColumnLimitsChecker] the checker of the target column
      # @param model_adapter [#cast_value] the adapter's object for the target table
      # @param value_mapping [Hash{String => Object}] the consumer's mapping of source values to the values to
      #   load; an empty Hash for no mapping
      def initialize(target_column:, source_column:, position:, limits_checker:, model_adapter:, value_mapping:)
        @target_column = target_column
        @source_column = source_column
        @position = position
        @limits_checker = limits_checker
        @value_mapping = value_mapping
        @model_adapter = model_adapter
        @empty = 0
        @compatible_values = DistinctValues.new(listed_value_class: CompatibleValue)
        @incompatible_values = DistinctValues.new(listed_value_class: IncompatibleValue)
      end

      # @return [String] the source column the cells are read from
      attr_reader :source_column

      # Records the cell of one row.
      #
      # @param cell [String, nil] the value of the source column in one row; nil for an empty cell
      # @return [void]
      def add_cell(cell:)
        if cell.nil?
          @empty += 1
          return
        end

        mapped_value = @value_mapping.fetch(cell, cell)

        if Utilities.blank?(value: mapped_value)
          @empty += 1
          return
        end

        record_value(value: cell, mapped_value: mapped_value)
      end

      # @return [ColumnSummary] what the summary_builder holds now
      def summary
        ColumnSummary.new(
          source_column: @source_column,
          position: @position,
          empty: @empty,
          distinct_values: DistinctValueLists.new(
            compatible: @compatible_values.values,
            incompatible: @incompatible_values.values,
            compatible_count: @compatible_values.total_count,
            incompatible_count: @incompatible_values.total_count
          ),
          value_mapping: @value_mapping
        )
      end

      private

      # A value that is already listed is only counted, because the list it is in says whether it fits. Only a
      # new value is cast and checked.
      def record_value(value:, mapped_value:)
        if @compatible_values.listed?(value: value)
          @compatible_values.record(value: value)
        elsif @incompatible_values.listed?(value: value)
          @incompatible_values.record(value: value)
        else
          record_new_value(value: value, mapped_value: mapped_value)
        end
      end

      def record_new_value(value:, mapped_value:)
        cast_result = @model_adapter.cast_value(column_name: @target_column, value: mapped_value)
        mapping_applied = @value_mapping.key?(value)

        unless cast_result.castable
          @incompatible_values.record(
            value: value, mapping_applied: mapping_applied, mapped_value: mapped_value, casted_to: nil,
            reason: :value_not_castable
          )
          return
        end

        violation = @limits_checker.violation_of(value: cast_result.cast_value)

        if violation.nil?
          @compatible_values.record(
            value: value, mapping_applied: mapping_applied, mapped_value: mapped_value, casted_to: cast_result.json_value
          )
        else
          @incompatible_values.record(
            value: value, mapping_applied: mapping_applied, mapped_value: mapped_value,
            casted_to: cast_result.json_value, reason: violation.code
          )
        end
      end
    end
  end
end
