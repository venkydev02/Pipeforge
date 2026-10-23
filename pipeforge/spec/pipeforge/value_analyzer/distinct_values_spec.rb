# frozen_string_literal: true

RSpec.describe Pipeforge::ValueAnalyzer::DistinctValues do
  subject(:distinct_values) { described_class.new(cap: cap) }

  let(:cap) { nil }

  # A list holding each value with the count it is given.
  def list_of(value_counts, cap: nil)
    described_class.new(cap: cap).tap do |list|
      value_counts.each { |value, count| list.record(value: value, count: count) }
    end
  end

  describe "#record" do
    it "counts a value once by default" do
      distinct_values.record(value: "a")

      expect(distinct_values.value_counts).to eq("a" => 1)
    end

    it "counts a value the number of times it is given" do
      distinct_values.record(value: "a", count: 5)

      expect(distinct_values.value_counts).to eq("a" => 5)
    end

    it "adds to the count of a value that is already listed" do
      2.times { distinct_values.record(value: "a") }
      distinct_values.record(value: "a", count: 3)

      expect(distinct_values.value_counts).to eq("a" => 5)
    end

    context "without a cap" do
      it "lists every value" do
        distinct_values.record(value: "a")
        distinct_values.record(value: "b")
        distinct_values.record(value: "c")
        distinct_values.record(value: "d")
        distinct_values.record(value: "e")

        expect(distinct_values.value_counts.keys).to eq(%w[a b c d e])
      end
    end

    context "with a cap" do
      let(:cap) { 2 }

      it "lists a new value while there is room" do
        distinct_values.record(value: "a")
        distinct_values.record(value: "b")

        expect(distinct_values.value_counts.keys).to eq(%w[a b])
      end

      it "leaves out a new value once the list is full" do
        distinct_values.record(value: "a")
        distinct_values.record(value: "b")
        distinct_values.record(value: "c")

        expect(distinct_values.value_counts.keys).to eq(%w[a b])
      end

      it "keeps counting a value that is already listed after the list is full" do
        distinct_values.record(value: "a")
        distinct_values.record(value: "b")
        distinct_values.record(value: "c")
        distinct_values.record(value: "a", count: 4)

        expect(distinct_values.value_counts).to eq("a" => 5, "b" => 1)
      end
    end

    context "with a cap of zero" do
      let(:cap) { 0 }

      it "lists nothing" do
        distinct_values.record(value: "a")

        expect(distinct_values.value_counts).to be_empty
      end
    end
  end

  describe "#merge" do
    let(:earlier_list) { list_of({"a" => 1, "b" => 2}, cap: cap) }
    let(:later_list) { list_of({"b" => 3, "c" => 1}) }

    it "returns a new list" do
      merged = earlier_list.merge(later: later_list)

      expect(merged).to be_a(described_class)
      expect(merged).not_to equal(earlier_list)
    end

    it "adds the counts of a value both lists have" do
      expect(earlier_list.merge(later: later_list).value_counts).to eq("a" => 1, "b" => 5, "c" => 1)
    end

    it "does not change the earlier list" do
      expect { earlier_list.merge(later: later_list) }.not_to change { earlier_list.value_counts }
    end

    it "does not change the later list" do
      expect { earlier_list.merge(later: later_list) }.not_to change { later_list.value_counts }
    end

    context "when the earlier list has a cap" do
      let(:cap) { 2 }

      it "keeps the values that appeared first and leaves out the rest" do
        expect(earlier_list.merge(later: later_list).value_counts).to eq("a" => 1, "b" => 5)
      end
    end

    context "when the later list is longer than the earlier cap" do
      let(:cap) { 3 }
      let(:later_list) { list_of({"c" => 1, "d" => 1, "e" => 1}) }

      it "lists only as many new values as there is room for" do
        expect(earlier_list.merge(later: later_list).value_counts.keys).to eq(%w[a b c])
      end
    end
  end

  describe "#values" do
    it "is empty for an empty list" do
      expect(distinct_values.values).to eq([])
    end

    it "puts the most frequent value first" do
      list = list_of({"a" => 1, "b" => 3, "c" => 2})

      expect(list.values.map { |listed| listed[:value] }).to eq(%w[b c a])
    end

    it "keeps the order of first appearance for values with the same count" do
      list = list_of({"b" => 1, "a" => 3, "c" => 1, "d" => 3})

      expect(list.values).to eq(
        [{value: "a", count: 3}, {value: "d", count: 3}, {value: "b", count: 1}, {value: "c", count: 1}]
      )
    end

    it "does not change the list" do
      list = list_of({"b" => 1, "a" => 3})

      expect { list.values }.not_to change { list.value_counts.to_a }
    end
  end
end
