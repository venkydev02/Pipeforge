# frozen_string_literal: true

module Pipeforge
  module ValueAnalyzer
    # The different values of one list, with how often each occurs.
    #
    # A value that is already listed is always counted. A new value is listed only while the
    # list holds fewer than +cap+ values; after that it is left out and not counted anywhere
    # in the list. Mutable: {#record} is the only method that changes it.
    class DistinctValues
      # @param cap [Integer, nil] the most different values to list; nil lists every value
      def initialize(cap:)
        @cap = cap
        @entries = {}
      end

      # Counts a value, listing it first when it is new and there is room.
      #
      # @param value [String]
      # @param count [Integer] how many times the value occurred
      # @param casted_to [String, nil] the value as it would be loaded, when that is not the value itself
      # @return [void]
      def record(value:, count: 1, casted_to: nil)
        if @entries.key?(value)
          @entries[value][:count] += count
        elsif @cap.nil? || @entries.size < @cap
          # casted_to depends only on the value, so the one given the first time it is listed is kept.
          @entries[value] = {count: count, casted_to: casted_to}
        end
      end

      # Merges a later list into this one, which came earlier in the file. The cap of this list
      # applies, so the values that appeared first are the ones kept.
      #
      # @param later [DistinctValues]
      # @return [DistinctValues] a new list; neither input changes
      def merge(later:)
        merged = self.class.new(cap: @cap)

        [self, later].each do |list|
          list.entries.each do |value, entry|
            merged.record(value: value, count: entry[:count], casted_to: entry[:casted_to])
          end
        end

        merged
      end

      # The listed values, most frequent first. Values with the same count keep the order they
      # first appeared in, which keeps the result the same on every run.
      #
      # @return [Array<Hash>] +{value:, count:}+ entries; an entry has +casted_to:+ too when the value is
      #   loaded as something else than itself
      def values
        ranked_values = []

        @entries.each_with_index do |(value, entry), appearance|
          ranked_values << [value, entry, appearance]
        end

        ranked_values.sort_by! { |_value, entry, appearance| [-entry[:count], appearance] }
        ranked_values.map { |value, entry, _appearance| listed_entry(value: value, entry: entry) }
      end

      protected

      # @return [Hash{String => Hash}] each listed value with its +count+ and its +casted_to+ (nil when
      #   it is loaded as the value itself), in the order the values first appeared
      attr_reader :entries

      private

      def listed_entry(value:, entry:)
        listed = {value: value, count: entry[:count]}
        listed[:casted_to] = entry[:casted_to] unless entry[:casted_to].nil?

        listed
      end
    end
  end
end
