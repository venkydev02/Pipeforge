# frozen_string_literal: true

RSpec.describe Pipeforge::ColumnValueAnalyzer::DistinctValues do
  subject(:distinct_values) { described_class.new(listed_value_class: listed_value_class) }

  let(:listed_value_class) { Pipeforge::ColumnValueAnalyzer::CompatibleValue }

  # A list holding each value as many times as it is given, with the text itself as casted_to.
  def distinct_values_with(counts)
    described_class.new(listed_value_class: listed_value_class).tap do |list|
      counts.each { |value, count| count.times { list.record(value: value, casted_to: value) } }
    end
  end

  describe "#record" do
    it "counts a value once" do
      distinct_values.record(value: "a", casted_to: "a")

      expect(distinct_values.values).to eq([compatible_value(value: "a", count: 1, casted_to: "a")])
    end

    it "adds to the count of a value that is already listed" do
      3.times { distinct_values.record(value: "a", casted_to: "a") }

      expect(distinct_values.values).to eq([compatible_value(value: "a", count: 3, casted_to: "a")])
    end

    it "lists every different value" do
      %w[a b c d e].each { |value| distinct_values.record(value: value, casted_to: value) }

      expect(distinct_values.values.map(&:value)).to eq(%w[a b c d e])
    end

    it "lists a thousand and more different values" do
      1200.times { |number| distinct_values.record(value: number.to_s, casted_to: number) }

      expect(distinct_values.values.size).to eq(1200)
    end

    it "keeps the casted_to of the first time the value was recorded" do
      distinct_values.record(value: "1,000", casted_to: 1)
      distinct_values.record(value: "1,000", casted_to: 2)

      expect(distinct_values.values).to eq([compatible_value(value: "1,000", count: 2, casted_to: 1)])
    end

    it "keeps a casted_to that is nil" do
      distinct_values.record(value: "null", casted_to: nil)

      expect(distinct_values.values).to eq([compatible_value(value: "null", count: 1, casted_to: nil)])
    end

    it "keeps a casted_to that is false" do
      distinct_values.record(value: "no", casted_to: false)

      expect(distinct_values.values).to eq([compatible_value(value: "no", count: 1, casted_to: false)])
    end

    it "keeps a casted_to that is zero" do
      distinct_values.record(value: "abc", casted_to: 0)

      expect(distinct_values.values).to eq([compatible_value(value: "abc", count: 1, casted_to: 0)])
    end
  end

  describe "#listed?" do
    it "is false for a value that was not recorded" do
      expect(distinct_values.listed?(value: "a")).to be(false)
    end

    it "is true for a value that was recorded" do
      distinct_values.record(value: "a", casted_to: "a")

      expect(distinct_values.listed?(value: "a")).to be(true)
    end

    it "is false for another value" do
      distinct_values.record(value: "a", casted_to: "a")

      expect(distinct_values.listed?(value: "b")).to be(false)
    end
  end

  describe "#values" do
    it "is empty for an empty list" do
      expect(distinct_values.values).to eq([])
    end

    it "puts the most frequent value first" do
      list = distinct_values_with("a" => 1, "b" => 3, "c" => 2)

      expect(list.values.map(&:value)).to eq(%w[b c a])
    end

    it "keeps the order of first appearance for values with the same count" do
      list = distinct_values_with("b" => 1, "a" => 3, "c" => 1, "d" => 3)

      expect(list.values.map(&:value)).to eq(%w[a d b c])
    end

    it "does not change the list" do
      list = distinct_values_with("b" => 1, "a" => 3)

      expect(list.values).to eq(list.values)
    end

    context "when the listed value class is IncompatibleValue" do
      let(:listed_value_class) { Pipeforge::ColumnValueAnalyzer::IncompatibleValue }

      it "gives listed values with the reason recorded with the value" do
        distinct_values.record(value: "x", casted_to: nil, reason: :value_not_castable)

        expect(distinct_values.values).to eq(
          [incompatible_value(value: "x", count: 1, casted_to: nil, reason: :value_not_castable)]
        )
      end

      it "raises when a new value is recorded without the reason" do
        expect { distinct_values.record(value: "x", casted_to: nil) }.to raise_error(ArgumentError)
      end
    end
  end
end
