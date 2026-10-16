# frozen_string_literal: true

RSpec.describe Pipeforge::Fingerprint do
  subject(:fingerprint) { described_class.new }

  describe "#value" do
    it "is the SHA-256 of the text, as 64 hex characters" do
      expect(fingerprint.add(text: "abc").value).to eq("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    end

    it "is the same however the text is split into pieces" do
      split = described_class.new.add(text: "ab").add(text: "c")

      expect(split.value).to eq(described_class.new.add(text: "abc").value)
    end

    it "changes when the text changes" do
      expect(fingerprint.add(text: "abd").value).not_to eq(described_class.new.add(text: "abc").value)
    end
  end

  describe "#add" do
    it "returns the same fingerprint, so calls can be chained" do
      expect(fingerprint.add(text: "x")).to be(fingerprint)
    end
  end
end
