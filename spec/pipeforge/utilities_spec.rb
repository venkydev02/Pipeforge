# frozen_string_literal: true

RSpec.describe Pipeforge::Utilities do
  describe ".blank?" do
    context "with a string" do
      ["", " ", "  \t\n"].each do |value|
        it "is true for #{value.inspect}, which has nothing but whitespace" do
          expect(described_class.blank?(value: value)).to be true
        end
      end

      ["x", " x ", "0", "false"].each do |value|
        it "is false for #{value.inspect}" do
          expect(described_class.blank?(value: value)).to be false
        end
      end
    end

    context "with nil" do
      it "is true" do
        expect(described_class.blank?(value: nil)).to be true
      end
    end

    context "with another object that can be empty" do
      [[], {}, Set.new].each do |value|
        it "is true for the empty #{value.class}" do
          expect(described_class.blank?(value: value)).to be true
        end
      end

      [[nil], [""], {"a" => 1}, Set[1]].each do |value|
        it "is false for #{value.inspect}, which holds something" do
          expect(described_class.blank?(value: value)).to be false
        end
      end
    end

    context "with an object that cannot be empty" do
      [0, 1, 1.5, true, Object.new].each do |value|
        it "is false for #{value.class} #{value.inspect.sub(/0x\h+/, "")}" do
          expect(described_class.blank?(value: value)).to be false
        end
      end

      it "is false for false, so a value mapped to false is kept" do
        expect(described_class.blank?(value: false)).to be false
      end
    end
  end
end
