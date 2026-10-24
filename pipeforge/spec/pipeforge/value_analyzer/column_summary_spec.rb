# frozen_string_literal: true

RSpec.describe Pipeforge::ValueAnalyzer::ColumnSummary do
  let(:distinct_values_class) { Pipeforge::ValueAnalyzer::DistinctValues }

  # A summary as a chunk is measured: it knows its counts and lists, not yet its source column.
  def summary_of(empty: 0, fits: 0, total: 0, compatible: {}, incompatible: {}, source_column: nil, position: nil,
    value_mapping: {})
    described_class.new(
      source_column: source_column,
      position: position,
      empty: empty,
      type_compatibility: {fits: fits, total: total},
      distinct_values: {compatible: list_of(compatible), incompatible: list_of(incompatible)},
      value_mapping: value_mapping
    )
  end

  def list_of(value_counts)
    distinct_values_class.new(cap: nil).tap do |list|
      value_counts.each { |value, count| list.record(value: value, count: count) }
    end
  end

  describe ".empty" do
    subject(:summary) do
      described_class.empty(source_column: "Age", position: 2, value_mapping: {"x" => "0"}, cap: 5)
    end

    it "has the source column, the position and the value mapping it was given" do
      expect(summary).to have_attributes(source_column: "Age", position: 2, value_mapping: {"x" => "0"})
    end

    it "has nothing counted" do
      expect(summary).to have_attributes(empty: 0, type_compatibility: {fits: 0, total: 0})
    end

    it "has an empty list for each kind of value" do
      expect(summary.distinct_values.values).to all(have_attributes(value_counts: {}))
    end

    it "holds at most the cap of different values in each list" do
      lists = summary.distinct_values.values
      lists.each { |list| 7.times { |index| list.record(value: "v#{index}") } }

      expect(lists.map { |list| list.value_counts.size }).to eq([5, 5])
    end
  end

  describe "#merge" do
    subject(:merged) { earlier.merge(later: later) }

    let(:earlier) do
      summary_of(empty: 1, fits: 2, total: 3, compatible: {"a" => 2}, incompatible: {"x" => 1},
        source_column: "Age", position: 2)
    end
    let(:later) { summary_of(empty: 2, fits: 1, total: 4, compatible: {"a" => 1, "b" => 1}, incompatible: {"y" => 3}) }

    it "adds the empty counts" do
      expect(merged.empty).to eq(3)
    end

    it "adds the type compatibility counts" do
      expect(merged.type_compatibility).to eq(fits: 3, total: 7)
    end

    it "merges the compatible values" do
      expect(merged.distinct_values[:compatible].value_counts).to eq("a" => 3, "b" => 1)
    end

    it "merges the incompatible values" do
      expect(merged.distinct_values[:incompatible].value_counts).to eq("x" => 1, "y" => 3)
    end

    it "keeps the source column and the position of the earlier summary" do
      expect(merged).to have_attributes(source_column: "Age", position: 2)
    end

    it "keeps the value mapping of the earlier summary" do
      earlier_with_mapping = earlier.with(value_mapping: {"Active" => "1"})

      expect(earlier_with_mapping.merge(later: later).value_mapping).to eq("Active" => "1")
    end

    it "does not change the earlier summary" do
      expect { merged }.not_to change { earlier.type_compatibility }
    end
  end

  describe "#to_h" do
    subject(:hash) do
      summary_of(empty: 1, fits: 1, total: 2, compatible: {"30" => 1}, incompatible: {"x" => 1},
        source_column: "Age", position: 2, value_mapping: {"x" => "0"}).to_h
    end

    it "is made of plain JSON types, with each list as an array of value and count" do
      expect(hash).to eq(
        source_column: "Age",
        position: 2,
        empty: 1,
        type_compatibility: {fits: 1, total: 2},
        distinct_values: {
          compatible: [{value: "30", count: 1}],
          incompatible: [{value: "x", count: 1}]
        },
        value_mapping: {"x" => "0"}
      )
    end
  end
end
