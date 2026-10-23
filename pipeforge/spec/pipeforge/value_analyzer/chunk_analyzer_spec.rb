# frozen_string_literal: true

RSpec.describe Pipeforge::ValueAnalyzer::ChunkAnalyzer do
  let(:column_rules) { {"Age" => rules_for(type_checker: integer_type_checker)} }
  let(:integer_type_checker) { Pipeforge::ValueAnalyzer::TypeChecker.new(type_info: {type: "integer"}) }

  # The rules of one column; a column with no value mapping has {}.
  def rules_for(type_checker:, value_mapping: {})
    {type_checker: type_checker, value_mapping: value_mapping}
  end

  describe "#call" do
    subject(:profile) { described_class.call(rows: rows, column_rules: column_rules) }

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

      expect(described_class.call(rows: rows, column_rules: column_rules).columns["Age"].distinct_values[:compatible].value_counts.size).to eq(4)
    end

    context "with a value mapping for the column" do
      let(:column_rules) do
        {"Age" => rules_for(type_checker: integer_type_checker, value_mapping: {"x" => "7", "30" => nil})}
      end

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
      let(:column_rules) do
        {"Age" => rules_for(type_checker: integer_type_checker), "Name" => rules_for(type_checker: string_type_checker)}
      end
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
      let(:column_rules) { {"Age" => rules_for(type_checker: type_checker)} }
      let(:rows) { Array.new(5) { {"Age" => "30"} } + [{"Age" => "31"}] }

      it "checks each distinct value once, however often it appears" do
        profile

        expect(type_checker).to have_received(:fits?).with(text: "30").once
        expect(type_checker).to have_received(:fits?).with(text: "31").once
      end

      it "does not check empty values" do
        described_class.call(rows: [{"Age" => nil}], column_rules: column_rules)

        expect(type_checker).not_to have_received(:fits?)
      end
    end
  end
end
