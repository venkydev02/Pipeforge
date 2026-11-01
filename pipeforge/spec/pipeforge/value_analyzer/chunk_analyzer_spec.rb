# frozen_string_literal: true

RSpec.describe Pipeforge::ValueAnalyzer::ChunkAnalyzer do
  let(:mapped_columns) { {"age" => mapped_column(source_column: "Age", position: 1, type: "integer")} }
  # By default an adapter that reads a text as the type of its column, and cannot read any other text.
  let(:model_adapter) { FakeModelAdapter.reading(types: mapped_columns.transform_values { |entry| entry[:type] }) }

  # One mapped column, as the value analyzer prepares it: where its values are read from, the type
  # fields of its target column, and the checker of its limits built from them.
  def mapped_column(source_column:, position:, **fields)
    entry = {source_column: source_column, position: position}.merge(fields)

    entry.merge(limits_checker: Pipeforge::ColumnLimitsChecker.new(type_info: entry))
  end

  describe "#call" do
    subject(:profile) { described_class.call(rows: rows, mapped_columns: mapped_columns, model_adapter: model_adapter) }

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

      chunk_profile = described_class.call(rows: rows, mapped_columns: mapped_columns, model_adapter: model_adapter)

      expect(chunk_profile.columns["age"].distinct_values[:compatible].values.size).to eq(4)
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

      it "measures each one with its own limits" do
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

    context "with an adapter that records what it is asked" do
      let(:model_adapter) { FakeModelAdapter.lenient(types: {"age" => "integer"}) }
      let(:rows) { Array.new(5) { {"Age" => "30"} } + [{"Age" => "31"}] }

      before { allow(model_adapter).to receive(:cast_text).and_call_original }

      it "casts each distinct value once, however often it appears, for the column it is mapped to" do
        profile

        expect(model_adapter).to have_received(:cast_text).with(column_name: "age", text: "30").once
        expect(model_adapter).to have_received(:cast_text).with(column_name: "age", text: "31").once
      end

      it "does not cast empty values" do
        described_class.call(rows: [{"Age" => nil}], mapped_columns: mapped_columns, model_adapter: model_adapter)

        expect(model_adapter).not_to have_received(:cast_text)
      end

      context "with a column of a type that the core knows no limit for" do
        let(:mapped_columns) { {"data" => mapped_column(source_column: "Age", position: 1, type: "jsonb")} }

        it "casts it as for any other type, and a text the adapter reads fits" do
          expect(profile.columns["data"].type_compatibility).to eq(fits: 6, total: 6)
          expect(model_adapter).to have_received(:cast_text).with(column_name: "data", text: "30").once
        end
      end
    end

    context "when the adapter cannot read a value" do
      let(:model_adapter) { FakeModelAdapter.new(casts: ->(column_name:, text:) { (text == "x") ? nil : text.to_i }) }

      it "does not fit, and is listed as not fitting" do
        expect(profile.columns["age"].distinct_values[:incompatible].values).to eq([{value: "x", count: 1}])
      end
    end

    context "when the adapter cannot read a text of a column of a type with no limit" do
      let(:mapped_columns) { {"data" => mapped_column(source_column: "Age", position: 1, type: "uuid")} }
      let(:model_adapter) { FakeModelAdapter.new(casts: ->(column_name:, text:) { (text == "x") ? nil : text }) }

      it "does not fit" do
        expect(profile.columns["data"].distinct_values[:incompatible].values).to eq([{value: "x", count: 1}])
      end
    end

    context "when the cast value is a structure that is not written as text" do
      let(:mapped_columns) { {"tags" => mapped_column(source_column: "Age", position: 1, type: "array")} }
      let(:model_adapter) { FakeModelAdapter.new(casts: ->(column_name:, text:) { [text] }) }
      let(:rows) { [{"Age" => "30"}] }

      it "fits, and is not given a changed value" do
        expect(profile.columns["tags"].distinct_values[:compatible].values).to eq([{value: "30", count: 1}])
      end
    end

    context "when the cast value is past the limits of the column" do
      let(:mapped_columns) { {"age" => mapped_column(source_column: "Age", position: 1, type: "integer", limit: 1)} }
      let(:rows) { [{"Age" => "200"}, {"Age" => "5"}] }
      let(:model_adapter) { FakeModelAdapter.lenient(types: {"age" => "integer"}) }

      it "does not fit, and is not given a cast value when it is the text itself" do
        expect(profile.columns["age"].distinct_values[:incompatible].values).to eq([{value: "200", count: 1}])
        expect(profile.columns["age"].distinct_values[:compatible].values).to eq([{value: "5", count: 1}])
      end
    end

    context "when the cast is the reason the value does not fit" do
      let(:mapped_columns) do
        {
          "age" => mapped_column(source_column: "Age", position: 1, type: "integer", limit: 1),
          "fee" => mapped_column(source_column: "Fee", position: 2, type: "decimal", precision: 5, scale: 2)
        }
      end
      let(:model_adapter) { FakeModelAdapter.lenient(types: {"age" => "integer", "fee" => "decimal"}, scales: {"fee" => 2}) }
      let(:rows) { [{"Age" => "200.5", "Fee" => "999.999"}, {"Age" => "5", "Fee" => "999.99"}] }

      it "gives the cast value of an incompatible integer" do
        expect(profile.columns["age"].distinct_values[:incompatible].values).to eq(
          [{value: "200.5", count: 1, casted_to: "200"}]
        )
      end

      it "gives the cast value of an incompatible decimal, which shows the digit that rounding added" do
        expect(profile.columns["fee"].distinct_values[:incompatible].values).to eq(
          [{value: "999.999", count: 1, casted_to: "1000.0"}]
        )
      end

      it "does not give a cast value to a compatible value that is the text itself" do
        expect(profile.columns["age"].distinct_values[:compatible].values).to eq([{value: "5", count: 1}])
      end
    end

    context "with an adapter that casts leniently" do
      let(:model_adapter) { FakeModelAdapter.lenient(types: {"age" => "integer"}) }
      let(:rows) { ["30", "30", "1,000", "abc", "007"].map { |age| {"Age" => age} } }

      it "counts every value that the adapter reads as fitting" do
        expect(profile.columns["age"].type_compatibility).to eq(fits: 5, total: 5)
      end

      it "gives the value that the cast changes a text to, and none for a text that is the loaded value" do
        expect(profile.columns["age"].distinct_values[:compatible].values).to eq(
          [
            {value: "30", count: 2},
            {value: "1,000", count: 1, casted_to: "1"},
            {value: "abc", count: 1, casted_to: "0"},
            {value: "007", count: 1, casted_to: "7"}
          ]
        )
      end
    end

    context "with an adapter that casts a date and a decimal" do
      let(:mapped_columns) do
        {
          "day" => mapped_column(source_column: "Day", position: 1, type: "date"),
          "fee" => mapped_column(source_column: "Fee", position: 2, type: "decimal", precision: 10, scale: 2)
        }
      end
      let(:model_adapter) { FakeModelAdapter.lenient(types: {"day" => "date", "fee" => "decimal"}, scales: {"fee" => 2}) }
      let(:rows) { [{"Day" => "2024-02-03", "Fee" => "10.505"}, {"Day" => "2024-2-3", "Fee" => "10.5"}] }

      it "writes a date as YYYY-MM-DD and a decimal in plain notation, rounded to the scale" do
        expect(profile.columns["day"].distinct_values[:compatible].values).to eq(
          [{value: "2024-02-03", count: 1}, {value: "2024-2-3", count: 1, casted_to: "2024-02-03"}]
        )
        expect(profile.columns["fee"].distinct_values[:compatible].values).to eq(
          [{value: "10.505", count: 1, casted_to: "10.51"}, {value: "10.5", count: 1}]
        )
      end
    end
  end
end
