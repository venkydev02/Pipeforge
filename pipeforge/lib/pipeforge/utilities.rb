# frozen_string_literal: true

module Pipeforge
  # Small helpers that Ruby's core and standard library do not provide. Native methods are
  # used directly and do not belong here; add a helper only when no native call does the job.
  module Utilities
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
