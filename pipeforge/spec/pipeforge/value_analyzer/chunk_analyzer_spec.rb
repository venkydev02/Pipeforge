# frozen_string_literal: true

RSpec.describe Pipeforge::ValueAnalyzer::ChunkAnalyzer do
  let(:mapped_columns) { {"age" => mapped_column(source_column: "Age", position: 1, type: "integer")} }

  # One mapped column, as the value analyzer prepares it: where its values are read from, the type
  # fields of its target column, and the type checker built from them (unless one is given).
  def mapped_column(source_column:, position:, **fields)
    entry = {source_column: source_column, position: position}.merge(fields)
    return entry if entry.key?(:type_checker)

    entry.merge(type_checker: Pipeforge::ValueAnalyzer::TypeChecker.new(type_info: entry))
  end

  describe "#call" do
    subject(:profile) { described_class.call(rows: rows, mapped_columns: mapped_columns) }

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

    it "measures only the mapped columns, keyed by target column" do
      expect(profile.columns.keys).to eq(["age"])
    end

    it "counts the empty cells" do
      expect(profile.columns["age"].empty).to eq(1)
    end

    it "counts the non-empty values and how many fit the type" do
      expect(profile.columns["age"].type_compatibility).to eq(fits: 2, total: 3)
    end

    it "lists the values that fit, with how often each appeared" do
      expect(profile.columns["age"].distinct_values[:compatible].values).to eq([{value: "30", count: 2}])
    end

    it "lists the values that do not fit" do
      expect(profile.columns["age"].distinct_values[:incompatible].values).to eq([{value: "x", count: 1}])
    end

    it "gives the summary its source column, its position and its value mapping" do
      expect(profile.columns["age"]).to have_attributes(source_column: "Age", position: 1, value_mapping: {})
    end

    it "does not cap the lists of one chunk, so no value loses a count when chunks are merged" do
      rows = %w[1 2 3 4].map { |age| {"Age" => age} }

      expect(described_class.call(rows: rows, mapped_columns: mapped_columns).columns["age"].distinct_values[:compatible].value_counts.size).to eq(4)
    end

    context "with a value mapping for the column" do
      let(:mapped_columns) do
        {
          "age" => mapped_column(
            source_column: "Age", position: 1, type: "integer", value_mapping: {"x" => "7", "30" => nil}
          )
        }
      end

      it "measures a mapped value as the value it maps to" do
        # 30 (x2) maps to nothing and counts as empty; x maps to 7, which fits.
        expect(profile.columns["age"].type_compatibility).to eq(fits: 1, total: 1)
      end

      it "counts a value that maps to nothing as empty" do
        expect(profile.columns["age"].empty).to eq(3)
      end

      it "lists a mapped value as the value it maps to" do
        expect(profile.columns["age"].distinct_values[:compatible].values).to eq([{value: "7", count: 1}])
      end

      it "keeps the value mapping on the summary" do
        expect(profile.columns["age"].value_mapping).to eq("x" => "7", "30" => nil)
      end
    end

    context "with no rows" do
      let(:rows) { [] }

      it "still has the mapped column, with nothing counted" do
        expect(profile.columns["age"]).to have_attributes(empty: 0, type_compatibility: {fits: 0, total: 0})
      end
    end

    context "with several mapped columns" do
      let(:mapped_columns) do
        {
          "age" => mapped_column(source_column: "Age", position: 1, type: "integer"),
          "name" => mapped_column(source_column: "Name", position: 2, type: "string", max_length: 3)
        }
      end

      it "measures each one with its own type checker" do
        expect(profile.columns.transform_values(&:type_compatibility))
          .to eq("age" => {fits: 2, total: 3}, "name" => {fits: 2, total: 4})
      end
    end

    context "with two target columns that read the same source column" do
      let(:mapped_columns) do
        {
          "age" => mapped_column(source_column: "Age", position: 1, type: "integer"),
          "age_text" => mapped_column(source_column: "Age", position: 1, type: "string")
        }
      end

      it "measures the source column once for each of them, with that target's own type" do
        expect(profile.columns.transform_values(&:type_compatibility))
          .to eq("age" => {fits: 2, total: 3}, "age_text" => {fits: 3, total: 3})
      end
    end

    context "with a type checker that records what it is asked" do
      let(:type_checker) { instance_double(Pipeforge::ValueAnalyzer::TypeChecker, fits?: true) }
      let(:mapped_columns) do
        {"age" => mapped_column(source_column: "Age", position: 1, type: "integer", type_checker: type_checker)}
      end
      let(:rows) { Array.new(5) { {"Age" => "30"} } + [{"Age" => "31"}] }

      it "checks each distinct value once, however often it appears" do
        profile

        expect(type_checker).to have_received(:fits?).with(text: "30").once
        expect(type_checker).to have_received(:fits?).with(text: "31").once
      end

      it "does not check empty values" do
        described_class.call(rows: [{"Age" => nil}], mapped_columns: mapped_columns)

        expect(type_checker).not_to have_received(:fits?)
      end
    end
  end
end
