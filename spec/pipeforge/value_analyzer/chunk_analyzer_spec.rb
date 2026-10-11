# frozen_string_literal: true

RSpec.describe Pipeforge::ValueAnalyzer::ChunkAnalyzer do
  subject(:analyzer) { described_class.new(config: config, checkers: checkers) }

  let(:config) { build_configuration(source: {distinct_values_cap: 2}) }
  let(:checkers) { {"Age" => integer_checker} }
  let(:integer_checker) { Pipeforge::ValueAnalyzer::TypeChecker.new(type_info: {type: "integer"}) }

  describe "#call" do
    subject(:profile) { analyzer.call(rows: rows) }

    let(:rows) do
      [
        {"Age" => "30", "Name" => "Alice"},
        {"Age" => nil, "Name" => "Bob"},
        {"Age" => "x", "Name" => "Cara"},
        {"Age" => "30", "Name" => "Dan"}
      ]
    end

    it "returns a ChunkProfile" do
      expect(profile).to be_a(Pipeforge::ValueAnalyzer::ChunkProfile)
    end

    it "measures only the mapped columns" do
      expect(profile.columns.keys).to eq(["Age"])
    end

    it "counts the empty cells" do
      expect(profile.columns["Age"].empty).to eq(1)
    end

    it "counts the non-empty values and how many fit the type" do
      expect(profile.columns["Age"].type_compatibility).to eq(fits: 2, total: 3)
    end

    it "lists the values that fit, with how often each appeared" do
      expect(profile.columns["Age"].distinct_values[:compatible].values).to eq([{value: "30", count: 2}])
    end

    it "lists the values that do not fit" do
      expect(profile.columns["Age"].distinct_values[:incompatible].values).to eq([{value: "x", count: 1}])
    end

    it "leaves the target column and the position for the end of the scan" do
      expect(profile.columns["Age"]).to have_attributes(target_column: nil, position: nil)
    end

    it "does not cap the lists of one chunk, so no value loses a count when chunks are merged" do
      rows = %w[1 2 3 4].map { |age| {"Age" => age} }

      expect(analyzer.call(rows: rows).columns["Age"].distinct_values[:compatible].value_counts.size).to eq(4)
    end

    context "with no rows" do
      let(:rows) { [] }

      it "still has the mapped column, with nothing counted" do
        expect(profile.columns["Age"]).to have_attributes(empty: 0, type_compatibility: {fits: 0, total: 0})
      end
    end

    context "with several mapped columns" do
      let(:checkers) { {"Age" => integer_checker, "Name" => string_checker} }
      let(:string_checker) { Pipeforge::ValueAnalyzer::TypeChecker.new(type_info: {type: "string", max_length: 3}) }

      it "measures each one with its own checker" do
        expect(profile.columns.transform_values(&:type_compatibility))
          .to eq("Age" => {fits: 2, total: 3}, "Name" => {fits: 2, total: 4})
      end
    end

    context "with a checker that is told what it is asked" do
      let(:checker) { instance_double(Pipeforge::ValueAnalyzer::TypeChecker, fits?: true) }
      let(:checkers) { {"Age" => checker} }
      let(:rows) { Array.new(5) { {"Age" => "30"} } + [{"Age" => "31"}] }

      it "checks each distinct value once, however often it appears" do
        profile

        expect(checker).to have_received(:fits?).with(text: "30").once
        expect(checker).to have_received(:fits?).with(text: "31").once
      end

      it "does not check empty values" do
        analyzer.call(rows: [{"Age" => nil}])

        expect(checker).not_to have_received(:fits?)
      end
    end
  end

  describe "#empty_profile" do
    subject(:profile) { analyzer.empty_profile }

    let(:checkers) { {"Age" => integer_checker, "Name" => integer_checker} }

    it "has every mapped column" do
      expect(profile.columns.keys).to eq(%w[Age Name])
    end

    it "carries the configured cap on its lists, so the cap applies to what is merged into it" do
      lists = profile.columns.values.flat_map { |summary| summary.distinct_values.values }

      expect(lists).to all(have_attributes(cap: 2))
    end

    it "has nothing counted" do
      expect(profile.columns.values).to all(have_attributes(empty: 0, type_compatibility: {fits: 0, total: 0}))
    end
  end
end
