# frozen_string_literal: true

RSpec.describe Pipeforge::ColumnValueAnalyzer::DistinctValues do
  subject(:distinct_values) { described_class.new }

  # A list holding each value as many times as it is given.
  def list_of(counts)
    described_class.new.tap do |list|
      counts.each { |value, count| count.times { list.record(value: value) } }
    end
  end

  describe "#record" do
    it "counts a value once" do
      distinct_values.record(value: "a")

      expect(distinct_values.values).to eq([{value: "a", count: 1}])
    end

    it "adds to the count of a value that is already listed" do
      3.times { distinct_values.record(value: "a") }

      expect(distinct_values.values).to eq([{value: "a", count: 3}])
    end

    it "lists every different value" do
      %w[a b c d e].each { |value| distinct_values.record(value: value) }

      expect(distinct_values.values.map { |entry| entry[:value] }).to eq(%w[a b c d e])
    end

    it "lists a thousand and more different values" do
      1200.times { |number| distinct_values.record(value: number.to_s) }

      expect(distinct_values.values.size).to eq(1200)
    end
  end

  describe "#listed?" do
    it "is false for a value that was not recorded" do
      expect(distinct_values.listed?(value: "a")).to be(false)
    end

    it "is true for a value that was recorded" do
      distinct_values.record(value: "a")

      expect(distinct_values.listed?(value: "a")).to be(true)
    end

    it "is false for another value" do
      distinct_values.record(value: "a")

      expect(distinct_values.listed?(value: "b")).to be(false)
    end
  end

  describe "casted_to" do
    it "is given in the entry of a value that was recorded with it" do
      2.times { distinct_values.record(value: "1,000", casted_to: "1") }

      expect(distinct_values.values).to eq([{value: "1,000", count: 2, casted_to: "1"}])
    end

    it "is left out of the entry of a value that was recorded without it" do
      distinct_values.record(value: "30")

      expect(distinct_values.values).to eq([{value: "30", count: 1}])
    end

    it "is kept from the first time a value is listed" do
      distinct_values.record(value: "1,000", casted_to: "1")
      distinct_values.record(value: "1,000", casted_to: "other")

      expect(distinct_values.values).to eq([{value: "1,000", count: 2, casted_to: "1"}])
    end
  end

  describe "#values" do
    it "is empty for an empty list" do
      expect(distinct_values.values).to eq([])
    end

    it "puts the most frequent value first" do
      list = list_of("a" => 1, "b" => 3, "c" => 2)

      expect(list.values.map { |listed| listed[:value] }).to eq(%w[b c a])
    end

    it "keeps the order of first appearance for values with the same count" do
      list = list_of("b" => 1, "a" => 3, "c" => 1, "d" => 3)

      expect(list.values).to eq(
        [{value: "a", count: 3}, {value: "d", count: 3}, {value: "b", count: 1}, {value: "c", count: 1}]
      )
    end

    it "does not change the list" do
      list = list_of("b" => 1, "a" => 3)

      expect(list.values).to eq(list.values)
    end
  end
end
