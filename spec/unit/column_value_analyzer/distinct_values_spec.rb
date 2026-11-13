# frozen_string_literal: true

RSpec.describe Pipeforge::ColumnValueAnalyzer::DistinctValues do
  subject(:distinct_values) { described_class.new(listed_value_class: listed_value_class) }

  # The list builds whatever class it is given with value:, count: and the fields of the caller, so the spec gives it
  # a class of its own with a made-up field.
  let(:listed_value_class) { Data.define(:value, :count, :colour) }

  describe "#listed?" do
    context "when the list is empty" do
      it "lists no value" do
        expect(distinct_values.listed?(value: "a")).to be(false)
      end
    end

    context "when a value was recorded" do
      before { distinct_values.record(value: "a", colour: "red") }

      it "lists that value" do
        expect(distinct_values.listed?(value: "a")).to be(true)
      end

      it "does not list another value" do
        expect(distinct_values.listed?(value: "b")).to be(false)
      end
    end
  end

  describe "#total_count" do
    context "when the list is empty" do
      it "is 0" do
        expect(distinct_values.total_count).to eq(0)
      end
    end

    context "when values are recorded more than once" do
      before do
        distinct_values.record(value: "a", colour: "red")
        distinct_values.record(value: "a", colour: "red")
        distinct_values.record(value: "a", colour: "red")
        distinct_values.record(value: "b", colour: "red")
      end

      it "is how many times values were recorded, not how many different values there are" do
        expect(distinct_values.total_count).to eq(4)
      end
    end
  end

  describe "#record" do
    context "when a value is recorded once with a field" do
      before { distinct_values.record(value: "a", colour: "red") }

      it "lists it with a count of 1 and the field it was given" do
        expect(distinct_values.values).to eq([listed_value_class.new(value: "a", count: 1, colour: "red")])
      end
    end

    context "when the same value is recorded three times" do
      before do
        distinct_values.record(value: "a", colour: "red")
        distinct_values.record(value: "a", colour: "red")
        distinct_values.record(value: "a", colour: "red")
      end

      it "lists it once with a count of 3" do
        expect(distinct_values.values).to eq([listed_value_class.new(value: "a", count: 3, colour: "red")])
      end
    end

    context "when five different values are recorded" do
      before do
        distinct_values.record(value: "a", colour: "red")
        distinct_values.record(value: "b", colour: "red")
        distinct_values.record(value: "c", colour: "red")
        distinct_values.record(value: "d", colour: "red")
        distinct_values.record(value: "e", colour: "red")
      end

      it "lists all five" do
        expect(distinct_values.values.map(&:value)).to contain_exactly("a", "b", "c", "d", "e")
      end
    end

    context "when a value is recorded again with another field" do
      before do
        distinct_values.record(value: "a", colour: "red")
        distinct_values.record(value: "a", colour: "blue")
      end

      it "keeps the field of the first time and counts both" do
        expect(distinct_values.values).to eq([listed_value_class.new(value: "a", count: 2, colour: "red")])
      end
    end

    context "when a value is recorded again with no fields" do
      before do
        distinct_values.record(value: "a", colour: "red")
        distinct_values.record(value: "a")
      end

      it "keeps the field of the first time and counts both" do
        expect(distinct_values.values).to eq([listed_value_class.new(value: "a", count: 2, colour: "red")])
      end
    end

    context "when a new value is recorded without a field the listed value class needs" do
      it "raises an ArgumentError" do
        expect { distinct_values.record(value: "x") }.to raise_error(ArgumentError)
      end
    end

    context "when a new value is recorded with a field the listed value class does not have" do
      it "raises an ArgumentError" do
        expect { distinct_values.record(value: "x", colour: "red", size: "big") }.to raise_error(ArgumentError)
      end
    end
  end

  describe "#values" do
    context "when the list is empty" do
      it "is an empty list" do
        expect(distinct_values.values).to eq([])
      end
    end

    context "when the values occur a different number of times" do
      before do
        distinct_values.record(value: "a", colour: "red")
        distinct_values.record(value: "b", colour: "red")
        distinct_values.record(value: "b", colour: "red")
        distinct_values.record(value: "b", colour: "red")
        distinct_values.record(value: "c", colour: "red")
        distinct_values.record(value: "c", colour: "red")
      end

      it "gives the most frequent first" do
        expect(distinct_values.values.map(&:value)).to eq(%w[b c a])
      end
    end

    context "when values have the same count" do
      before do
        distinct_values.record(value: "b", colour: "red")
        distinct_values.record(value: "a", colour: "red")
        distinct_values.record(value: "a", colour: "red")
        distinct_values.record(value: "a", colour: "red")
        distinct_values.record(value: "c", colour: "red")
        distinct_values.record(value: "d", colour: "red")
        distinct_values.record(value: "d", colour: "red")
        distinct_values.record(value: "d", colour: "red")
      end

      it "keeps the order of first appearance among them" do
        expect(distinct_values.values.map(&:value)).to eq(%w[a d b c])
      end
    end

    # Ruby's sort_by keeps tied items in order only for short lists, and only when the counts differ, so a smaller
    # list or one count for every value would not catch a missing tie-break.
    context "when many values share two different counts" do
      let(:values_in_order_of_appearance) { (1..40).map { |number| format("value_%02d", number) } }
      let(:pairs_of_values) { values_in_order_of_appearance.each_slice(2).to_a }
      let(:values_recorded_twice) { pairs_of_values.map(&:first) }
      let(:values_recorded_once) { pairs_of_values.map(&:last) }

      before do
        values_in_order_of_appearance.each do |value|
          distinct_values.record(value: value, colour: "red")
        end
        values_recorded_twice.each do |value|
          distinct_values.record(value: value, colour: "red")
        end
      end

      it "keeps the order of first appearance among the values of each count" do
        expect(distinct_values.values.map(&:value)).to eq(values_recorded_twice + values_recorded_once)
      end
    end
  end
end
