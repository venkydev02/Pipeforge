# frozen_string_literal: true

module Pipeforge
  module ValueAnalyzer
    # The different values of one list, with how often each occurs.
    #
    # A value that is already listed is always counted. A new value is listed only while the
    # list holds fewer than +cap+ values; after that it is left out and not counted anywhere
    # in the list. Mutable: {#record} is the only method that changes it.
    class DistinctValues
      # @return [Hash{String => Integer}] each listed value with its count, in the order the
      #   values first appeared
      attr_reader :value_counts

      # @param cap [Integer, nil] the most different values to list; nil lists every value
      def initialize(cap:)
        @cap = cap
        @value_counts = {}
      end

      # Counts a value, listing it first when it is new and there is room.
      #
      # @param value [String]
      # @param count [Integer] how many times the value occurred
      # @return [void]
      def record(value:, count: 1)
        if @value_counts.key?(value)
          @value_counts[value] += count
        elsif @cap.nil? || @value_counts.size < @cap
          @value_counts[value] = count
        end
      end

      # Merges a later list into this one, which came earlier in the file. The cap of this list
      # applies, so the values that appeared first are the ones kept.
      #
      # @param later [DistinctValues]
      # @return [DistinctValues] a new list; neither input changes
      def merge(later:)
        merged = self.class.new(cap: @cap)

        @value_counts.each { |value, count| merged.record(value: value, count: count) }
        later.value_counts.each { |value, count| merged.record(value: value, count: count) }

        merged
      end

      # The listed values, most frequent first. Values with the same count keep the order they
      # first appeared in, which keeps the result the same on every run.
      #
      # @return [Array<Hash>] +{value:, count:}+ entries
      def values
        ranked_values = []

        @value_counts.each_with_index do |(value, count), appearance|
          ranked_values << [value, count, appearance]
        end

        ranked_values.sort_by! { |_value, count, appearance| [-count, appearance] }
        ranked_values.map { |value, count, _appearance| {value: value, count: count} }
      end
    end
  end
end
