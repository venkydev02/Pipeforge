# frozen_string_literal: true

require_relative "distinct_values"
require_relative "listed_values"

module Pipeforge
  module ColumnValueAnalyzer
    # The distinct texts of one column, split by whether the column accepts them. Each list holds every
    # different text, most frequent first, and the texts with the same count in the order they first appeared.
    #   compatible    Array<CompatibleValue>    the texts the column accepts
    #   incompatible  Array<IncompatibleValue>  the texts the column does not accept: +reason+ says why, either
    #                                           +:value_not_castable+ (the adapter could not cast the text) or
    #                                           the code of the limit the cast value breaks
    #                                           (+:value_too_long+, +:value_out_of_range+, +:value_not_allowed+)
    DistinctValueLists = Data.define(:compatible, :incompatible)

    # What the scan found out about one mapped target column. A Result holds it under the name of the
    # target column.
    #   source_column       String                 the source column it is read from
    #   position            Integer                the position of the source column in the file, starting at 1
    #   empty               Integer                how many cells are empty
    #   type_compatibility  Hash                   {fits:, total:}: how many of the non-empty values fit the
    #                                              target type
    #   distinct_values     DistinctValueLists     the texts that fit and the texts that do not
    #   value_mapping       Hash                   the consumer's mapping of source values to the values to load;
    #                                              the counts and the lists above describe the values after
    #                                              applying it, that is, what would be loaded
    ColumnSummary = Data.define(
      :source_column, :position, :empty, :type_compatibility, :distinct_values, :value_mapping
    ) do
      # Writes the summary in plain JSON types, to store it.
      #
      # @return [Hash] plain JSON types, with each list as an array of hashes with the fields of its listed values
      def to_h
        {
          source_column: source_column,
          position: position,
          empty: empty,
          type_compatibility: type_compatibility,
          distinct_values: {
            compatible: distinct_values.compatible.map(&:to_h),
            incompatible: distinct_values.incompatible.map(&:to_h)
          },
          value_mapping: value_mapping
        }
      end
    end

    # The running measurements of one mapped target column while the file is read, one row at a time: how
    # many cells are empty, how many values fit, and the distinct values that do and do not fit. Every
    # distinct value is kept. It is mutable: {#add_row} is the only method that changes it, and {#summary}
    # gives the finished {ColumnSummary}.
    #
    # A value with an entry in the value mapping of the column is measured, and listed, as the value it maps
    # to: that is what would be loaded. A value that maps to nil or to a blank counts as empty and is not listed.
    class ColumnSummaryBuilder
      # @param target_column [String] the target column the values are measured for
      # @param mapped_column [Hash] {source_column:, position:, limits_checker:, value_mapping: (optional)}, as
      #   the column values analyzer prepares it
      # @param model_adapter [#cast_text] the adapter's object for the target table
      def initialize(target_column:, mapped_column:, model_adapter:)
        @target_column = target_column
        @source_column = mapped_column.fetch(:source_column)
        @position = mapped_column[:position]
        @limits_checker = mapped_column.fetch(:limits_checker)
        @value_mapping = mapped_column.fetch(:value_mapping, {})
        @model_adapter = model_adapter
        @empty = 0
        @fits = 0
        @total = 0
        @compatible_values = DistinctValues.new(listed_value_class: CompatibleValue)
        @incompatible_values = DistinctValues.new(listed_value_class: IncompatibleValue)
      end

      # Records the cell of one row.
      #
      # @param row [Hash{String => String, nil}] one data row, as the reader yields it
      # @return [void]
      def add_row(row:)
        value = row[@source_column]

        if value.nil?
          @empty += 1
          return
        end

        loaded_value = @value_mapping.fetch(value, value)

        if Utilities.blank?(value: loaded_value)
          @empty += 1
          return
        end

        @total += 1
        record_value(text: loaded_value.to_s)
      end

      # @return [ColumnSummary] what the summary_builder holds now
      def summary
        ColumnSummary.new(
          source_column: @source_column,
          position: @position,
          empty: @empty,
          type_compatibility: {fits: @fits, total: @total},
          distinct_values: DistinctValueLists.new(
            compatible: @compatible_values.values,
            incompatible: @incompatible_values.values
          ),
          value_mapping: @value_mapping
        )
      end

      private

      # A value that is already listed is only counted, because the list it is in says whether it fits. Only a
      # new value is cast and checked.
      def record_value(text:)
        if @compatible_values.listed?(value: text)
          @fits += 1
          @compatible_values.record(value: text)
        elsif @incompatible_values.listed?(value: text)
          @incompatible_values.record(value: text)
        else
          record_new_value(text: text)
        end
      end

      def record_new_value(text:)
        cast_result = @model_adapter.cast_text(column_name: @target_column, text: text)

        unless cast_result.castable
          @incompatible_values.record(value: text, casted_to: nil, reason: :value_not_castable)
          return
        end

        violation = @limits_checker.violation_of(value: cast_result.cast_value)

        if violation.nil?
          @fits += 1
          @compatible_values.record(value: text, casted_to: cast_result.json_value)
        else
          @incompatible_values.record(value: text, casted_to: cast_result.json_value, reason: violation.code)
        end
      end
    end
  end
end
