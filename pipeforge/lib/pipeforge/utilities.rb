# frozen_string_literal: true

module Pipeforge
  # Small helpers that Ruby's core and standard library do not provide. Native methods are
  # used directly and do not belong here; add a helper only when no native call does the job.
  module Utilities
    # The largest finite number a 4-byte (single precision) float holds.
    SINGLE_FLOAT_MAX = 3.4028234663852886e38

    # The most significand bits of a float column that is single precision (24); a column with a
    # larger limit, or none, is double precision.
    SINGLE_FLOAT_LIMIT = 24

    # The largest finite number a float column of that size holds. No native call gives it: Ruby's
    # +Float::MAX+ is the double precision maximum only.
    #
    # @param limit [Integer, nil] the +limit+ of the float column: 24 or less for single precision
    #   (4 bytes), anything larger or nil for double precision (8 bytes)
    # @return [Float]
    def self.largest_float(limit:)
      return SINGLE_FLOAT_MAX if !limit.nil? && limit <= SINGLE_FLOAT_LIMIT

      Float::MAX
    end

    # Whether a value is a whole number of at least 1. Used for a count that must be positive (a chunk size, a
    # threshold).
    #
    # @param value [Object]
    # @return [Boolean]
    def self.positive_whole_number?(value:)
      value.is_a?(Integer) && value >= 1
    end

    # Whether a value is a whole number of at least 0. Used for a count that may be zero (an offset).
    #
    # @param value [Object]
    # @return [Boolean]
    def self.non_negative_whole_number?(value:)
      value.is_a?(Integer) && value >= 0
    end

    # Whether a value counts as empty: nil, a string with nothing but whitespace, or another
    # object that is itself empty (an empty array, hash or set). Anything else is not empty,
    # including false and 0, so a value mapped to false is loaded as false. (ActiveSupport's
    # +blank?+ is not used because it returns true for false.)
    #
    # @param value [Object]
    # @return [Boolean]
    def self.blank?(value:)
      return true if value.nil?
      return value.strip.empty? if value.is_a?(String)
      return value.empty? if value.respond_to?(:empty?)

      false
    end
  end
end
