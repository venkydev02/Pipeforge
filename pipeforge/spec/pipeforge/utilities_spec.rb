# frozen_string_literal: true

RSpec.describe Pipeforge::Utilities do
  describe ".blank?" do
    context "with a string" do
      it "is true for an empty string" do
        expect(described_class.blank?(value: "")).to be true
      end

      it "is true for one space" do
        expect(described_class.blank?(value: " ")).to be true
      end

      it "is true for tabs and newlines" do
        expect(described_class.blank?(value: "  \t\n")).to be true
      end

      it "is false for text" do
        expect(described_class.blank?(value: "x")).to be false
      end

      it "is false for text with spaces around it" do
        expect(described_class.blank?(value: " x ")).to be false
      end

      it "is false for the text 0" do
        expect(described_class.blank?(value: "0")).to be false
      end

      it "is false for the text false" do
        expect(described_class.blank?(value: "false")).to be false
      end
    end

    context "with nil" do
      it "is true" do
        expect(described_class.blank?(value: nil)).to be true
      end
    end

    context "with another object that can be empty" do
      it "is true for an empty array" do
        expect(described_class.blank?(value: [])).to be true
      end

      it "is true for an empty hash" do
        expect(described_class.blank?(value: {})).to be true
      end

      it "is true for an empty set" do
        expect(described_class.blank?(value: Set.new)).to be true
      end

      it "is false for an array that holds something, even nil" do
        expect(described_class.blank?(value: [nil])).to be false
      end

      it "is false for an array that holds an empty string" do
        expect(described_class.blank?(value: [""])).to be false
      end

      it "is false for a hash that holds something" do
        expect(described_class.blank?(value: {"a" => 1})).to be false
      end

      it "is false for a set that holds something" do
        expect(described_class.blank?(value: Set[1])).to be false
      end
    end

    context "with an object that cannot be empty" do
      it "is false for zero" do
        expect(described_class.blank?(value: 0)).to be false
      end

      it "is false for a whole number" do
        expect(described_class.blank?(value: 1)).to be false
      end

      it "is false for a decimal" do
        expect(described_class.blank?(value: 1.5)).to be false
      end

      it "is false for true" do
        expect(described_class.blank?(value: true)).to be false
      end

      it "is false for false, so a value mapped to false is kept" do
        expect(described_class.blank?(value: false)).to be false
      end

      it "is false for a plain object" do
        expect(described_class.blank?(value: Object.new)).to be false
      end
    end
  end

  describe ".largest_float" do
    it "is the double precision maximum when the column has no limit" do
      expect(described_class.largest_float(limit: nil)).to eq(Float::MAX)
    end

    it "is the double precision maximum for a limit of 53" do
      expect(described_class.largest_float(limit: 53)).to eq(Float::MAX)
    end

    it "is the single precision maximum for a limit of 24" do
      expect(described_class.largest_float(limit: 24)).to eq(3.4028234663852886e38)
    end

    it "is the single precision maximum for a limit below 24" do
      expect(described_class.largest_float(limit: 10)).to eq(3.4028234663852886e38)
    end

    it "is the double precision maximum for a limit just above 24" do
      expect(described_class.largest_float(limit: 25)).to eq(Float::MAX)
    end
  end
end
