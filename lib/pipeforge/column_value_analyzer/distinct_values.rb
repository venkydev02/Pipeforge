# frozen_string_literal: true

module Pipeforge
  module ColumnValueAnalyzer
    # The different values of one list, with how often each occurs. Every value is kept. Mutable:
    # {#record} is the only method that changes it.
    class DistinctValues
      def initialize
        @entries = {}
      end

      # @param value [String]
      # @return [Boolean] whether the value is listed
      def listed?(value:)
        @entries.key?(value)
      end

      # Counts one occurrence of a value, listing it first when it is new.
      #
      # @param value [String]
      # @param casted_to [String, nil] the value as it would be loaded, when that is not the value itself
      # @return [void]
      def record(value:, casted_to: nil)
        if @entries.key?(value)
          @entries[value][:count] += 1
        else
          # casted_to depends only on the value, so the one given the first time it is listed is kept.
          entry = {value: value, count: 1}
          entry[:casted_to] = casted_to unless casted_to.nil?
          @entries[value] = entry
        end
      end

      # The listed values, most frequent first. Values with the same count keep the order they
      # first appeared in, which keeps the result the same on every run.
      #
      # @return [Array<Hash>] +{value:, count:}+ entries; an entry has +casted_to:+ too when the value is
      #   loaded as something else than itself
      def values
        # The position breaks ties: sort_by does not keep equal items in the order they were listed.
        @entries.values.sort_by.with_index { |entry, appearance| [-entry[:count], appearance] }
      end
    end
  end
end
