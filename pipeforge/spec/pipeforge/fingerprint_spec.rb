# frozen_string_literal: true

RSpec.describe Pipeforge::Fingerprint do
  subject(:fingerprint) { described_class.new }

  # The fingerprint of the pieces of text, added in that order.
  def fingerprint_of(*pieces)
    described_class.new.tap { |new_fingerprint| pieces.each { |piece| new_fingerprint.add(text: piece) } }.value
  end

  describe "#value" do
    it "is the SHA-256 of the text, as 64 hex characters" do
      expect(fingerprint_of("abc")).to eq("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    end

    it "is the same however the text is split into pieces" do
      expect(fingerprint_of("ab", "c")).to eq(fingerprint_of("abc"))
    end

    it "changes when the text changes" do
      expect(fingerprint_of("abd")).not_to eq(fingerprint_of("abc"))
    end

    it "changes when the order of the pieces changes" do
      expect(fingerprint_of("a", "b")).not_to eq(fingerprint_of("b", "a"))
    end
  end
end
