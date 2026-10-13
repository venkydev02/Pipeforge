# frozen_string_literal: true

RSpec.describe Pipeforge::ValueAnalyzer::ChunkAnalyzer do
  subject(:analyzer) do
    described_class.new(config: config, type_checkers: type_checkers, value_mappings: value_mappings)
  end

  let(:config) { build_configuration(source: {distinct_values_cap: 2}) }
  let(:type_checkers) { {"Age" => integer_type_checker} }
  let(:value_mappings) { {} }
  let(:integer_type_checker) { Pipeforge::ValueAnalyzer::TypeChecker.new(type_info: {type: "integer"}) }

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

    context "with a value mapping for the column" do
      let(:value_mappings) { {"Age" => {"x" => "7", "30" => nil}} }

      it "measures a mapped value as the value it maps to" do
        # 30 (x2) maps to nothing and counts as empty; x maps to 7, which fits.
        expect(profile.columns["Age"].type_compatibility).to eq(fits: 1, total: 1)
      end

      it "counts a value that maps to nothing as empty" do
        expect(profile.columns["Age"].empty).to eq(3)
      end

      it "lists a mapped value as the value it maps to" do
        expect(profile.columns["Age"].distinct_values[:compatible].values).to eq([{value: "7", count: 1}])
      end

      it "leaves the value mapping for the end of the scan, like the target column" do
        expect(profile.columns["Age"].value_mapping).to eq({})
      end
    end

    context "with no rows" do
      let(:rows) { [] }

      it "still has the mapped column, with nothing counted" do
        expect(profile.columns["Age"]).to have_attributes(empty: 0, type_compatibility: {fits: 0, total: 0})
      end
    end

    context "with several mapped columns" do
      let(:type_checkers) { {"Age" => integer_type_checker, "Name" => string_type_checker} }
      let(:string_type_checker) do
        Pipeforge::ValueAnalyzer::TypeChecker.new(type_info: {type: "string", max_length: 3})
      end

      it "measures each one with its own type checker" do
        expect(profile.columns.transform_values(&:type_compatibility))
          .to eq("Age" => {fits: 2, total: 3}, "Name" => {fits: 2, total: 4})
      end
    end

    context "with a type checker that records what it is asked" do
      let(:type_checker) { instance_double(Pipeforge::ValueAnalyzer::TypeChecker, fits?: true) }
      let(:type_checkers) { {"Age" => type_checker} }
      let(:rows) { Array.new(5) { {"Age" => "30"} } + [{"Age" => "31"}] }

      it "checks each distinct value once, however often it appears" do
        profile

        expect(type_checker).to have_received(:fits?).with(text: "30").once
        expect(type_checker).to have_received(:fits?).with(text: "31").once
      end

      it "does not check empty values" do
        analyzer.call(rows: [{"Age" => nil}])

        expect(type_checker).not_to have_received(:fits?)
      end
    end
  end

  describe "#empty_profile" do
    subject(:profile) { analyzer.empty_profile }

    let(:type_checkers) { {"Age" => integer_type_checker, "Name" => integer_type_checker} }

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
