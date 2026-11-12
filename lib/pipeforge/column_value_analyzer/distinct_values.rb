# frozen_string_literal: true

require_relative "listed_values"

module Pipeforge
  module ColumnValueAnalyzer
    # The different values of one list, with how often each occurs. Every value is kept. Mutable:
    # {#record} is the only method that changes it.
    class DistinctValues
      # @param listed_value_class [Class] {CompatibleValue} or {IncompatibleValue}: the shape of every value the
      #   list gives
      def initialize(listed_value_class:)
        @listed_value_class = listed_value_class
        @listed_values = {}
      end

      # @param value [String]
      # @return [Boolean] whether the value is listed
      def listed?(value:)
        @listed_values.key?(value)
      end

      # Counts one occurrence of a value, listing it first when it is new.
      #
      # @param value [String]
      # @param listed_value_fields [Hash] the other fields of the listed value class (+casted_to:+, and +reason:+
      #   for an {IncompatibleValue}); only the ones given with the first occurrence are kept
      # @return [void]
      # @raise [ArgumentError] when a new value is recorded without a field the listed value class needs
      def record(value:, **listed_value_fields)
        listed_value = @listed_values[value]

        if listed_value.nil?
          # They depend only on the value, so the ones given the first time are kept.
          @listed_values[value] = @listed_value_class.new(value: value, count: 1, **listed_value_fields)
          return
        end

        # A listed value cannot change, so the counted copy takes its place.
        @listed_values[value] = listed_value.with(count: listed_value.count + 1)
      end

      # The listed values, most frequent first. Values with the same count keep the order they
      # first appeared in, which keeps the result the same on every run.
      #
      # @return [Array<CompatibleValue, IncompatibleValue>] one value of the list's listed value class for each
      #   different value
      def values
        # The position breaks ties: sort_by does not keep equal items in the order they were listed.
        @listed_values.values.sort_by.with_index { |listed_value, appearance| [-listed_value.count, appearance] }
      end
    end
  end
end
