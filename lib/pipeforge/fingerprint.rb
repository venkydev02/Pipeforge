# frozen_string_literal: true

require "digest"

module Pipeforge
  # A SHA-256 fingerprint of text. The text is added in pieces, in order, and the fingerprint is
  # read at the end, so the whole text never has to be held in memory at once.
  #
  # @example
  #   fingerprint = Pipeforge::Fingerprint.new
  #   fingerprint.add(text: "first piece")
  #   fingerprint.add(text: "second piece")
  #   fingerprint.value # => 64 hex characters
  class Fingerprint
    def initialize
      @digest = Digest::SHA256.new
    end

    # @param text [String] the next piece of text; pieces are joined in the order they are added
    # @return [self]
    def add(text:)
      @digest.update(text)
      self
    end

    # @return [String] the fingerprint of everything added so far, as 64 hex characters
    def value
      @digest.hexdigest
    end
  end
end
