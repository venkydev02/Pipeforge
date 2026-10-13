# frozen_string_literal: true

RSpec.describe Pipeforge::ValueAnalyzer::ChunkProfile do
  let(:summary_class) { Pipeforge::ValueAnalyzer::ColumnSummary }
  let(:distinct_values_class) { Pipeforge::ValueAnalyzer::DistinctValues }

  # A profile of one column "A" as a chunk would report it: these compatible values, every
  # value fitting, and a list without a cap (a chunk keeps every value).
  def profile_counting(compatible_counts)
    compatible = distinct_values_class.new(cap: nil)
    compatible_counts.each { |value, count| compatible.record(value: value, count: count) }
    total = compatible_counts.values.sum

    summary = summary_class.new(
      target_column: nil,
      position: nil,
      empty: 0,
      type_compatibility: {fits: total, total: total},
      distinct_values: {compatible: compatible, incompatible: distinct_values_class.new(cap: nil)},
      value_mapping: {}
    )

    described_class.new(columns: {"A" => summary})
  end

  describe ".empty" do
    subject(:profile) { described_class.empty(source_columns: %w[B A], cap: 5) }

    it "has a summary for every source column, in the order given" do
      expect(profile.columns.keys).to eq(%w[B A])
    end

    it "makes each one an empty ColumnSummary" do
      expect(profile.columns.values).to all(
        be_a(summary_class).and(have_attributes(empty: 0, type_compatibility: {fits: 0, total: 0}))
      )
    end

    it "gives the cap to the lists of every column" do
      lists = profile.columns.values.flat_map { |summary| summary.distinct_values.values }

      expect(lists).to all(have_attributes(cap: 5))
    end

    context "with no source columns" do
      subject(:profile) { described_class.empty(source_columns: [], cap: 5) }

      it "has no columns" do
        expect(profile.columns).to be_empty
      end
    end
  end

  describe "#merge" do
    subject(:merged) { earlier.merge(later: later) }

    let(:earlier) { profile_counting({"x" => 2}) }
    let(:later) { profile_counting({"x" => 1, "y" => 3}) }

    it "adds the counts of the later profile to the earlier one" do
      expect(merged.columns["A"].type_compatibility).to eq(fits: 6, total: 6)
    end

    it "merges the values of each column" do
      expect(merged.columns["A"].distinct_values[:compatible].value_counts).to eq("x" => 3, "y" => 3)
    end

    it "returns a new profile and leaves both as they were" do
      expect { merged }.not_to change { [earlier.columns["A"].type_compatibility, later.columns["A"].type_compatibility] }
    end

    context "when the earlier profile is empty and has a cap" do
      let(:earlier) { described_class.empty(source_columns: ["A"], cap: 2) }
      let(:later) { profile_counting({"a" => 1, "b" => 1, "c" => 1, "d" => 1}) }

      it "caps the values of the first chunk as well" do
        expect(merged.columns["A"].distinct_values[:compatible].value_counts.keys).to eq(%w[a b])
      end
    end

    context "when the later profile has a column the earlier one does not" do
      let(:earlier) { described_class.empty(source_columns: %w[A B], cap: nil) }

      it "raises KeyError, because every profile holds the same columns" do
        expect { merged }.to raise_error(KeyError)
      end
    end
  end
end
