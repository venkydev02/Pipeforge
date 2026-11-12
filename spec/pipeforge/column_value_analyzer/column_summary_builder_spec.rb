# frozen_string_literal: true

RSpec.describe Pipeforge::ColumnValueAnalyzer::ColumnSummaryBuilder do
  subject(:summary_builder) do
    described_class.new(target_column: "age", mapped_column: mapped_column, model_adapter: model_adapter)
  end

  let(:type_fields) { {type: "integer"} }
  let(:value_mapping) { nil }
  let(:model_adapter) { FakeModelAdapter.reading(types: {"age" => "integer"}) }
  let(:mapped_column) do
    entry = {source_column: "Age", position: 1}.merge(type_fields)
    entry[:value_mapping] = value_mapping unless value_mapping.nil?

    entry.merge(limits_checker: Pipeforge::ColumnLimitsChecker.new(type_info: entry))
  end

  # Records one row for each cell, in order. A nil is an empty cell.
  def add_cells(*cells)
    cells.each { |cell| summary_builder.add_row(row: {"Age" => cell, "Name" => "ignored"}) }
  end

  describe "#summary" do
    subject(:summary) { summary_builder.summary }

    context "before any row is added" do
      it "has nothing counted" do
        expect(summary).to have_attributes(empty: 0, type_compatibility: {fits: 0, total: 0})
        expect(summary.distinct_values.compatible).to eq([])
        expect(summary.distinct_values.incompatible).to eq([])
      end

      it "gives the distinct values as the two lists, each an array of its listed values" do
        expect(summary.distinct_values).to be_a(Pipeforge::ColumnValueAnalyzer::DistinctValueLists)
      end

      it "has the source column, the position and an empty value mapping" do
        expect(summary).to have_attributes(source_column: "Age", position: 1, value_mapping: {})
      end
    end

    context "with empty cells and values" do
      before { add_cells("30", nil, "x", "30") }

      it "counts the empty cells" do
        expect(summary.empty).to eq(1)
      end

      it "counts the non-empty values and how many fit the type" do
        expect(summary.type_compatibility).to eq(fits: 2, total: 3)
      end

      it "lists the values that fit, with how often each appeared" do
        expect(summary.distinct_values.compatible).to eq([compatible_value(value: "30", count: 2, casted_to: 30)])
      end

      it "lists the values that do not fit, with the reason that the adapter could not cast them" do
        expect(summary.distinct_values.incompatible)
          .to eq([incompatible_value(value: "x", count: 1, casted_to: nil, reason: :value_not_castable)])
      end
    end

    context "with a value that the cast changes" do
      let(:model_adapter) { FakeModelAdapter.lenient(types: {"age" => "integer"}) }

      before { add_cells("30", "30", "1,000", "abc", "007") }

      it "counts every value the adapter reads as fitting" do
        expect(summary.type_compatibility).to eq(fits: 5, total: 5)
      end

      it "gives the value each text is cast to, the one that is the text itself included" do
        expect(summary.distinct_values.compatible).to eq(
          [
            compatible_value(value: "30", count: 2, casted_to: 30),
            compatible_value(value: "1,000", count: 1, casted_to: 1),
            compatible_value(value: "abc", count: 1, casted_to: 0),
            compatible_value(value: "007", count: 1, casted_to: 7)
          ]
        )
      end
    end

    context "with a value that does not fit because of the cast" do
      let(:type_fields) { {type: "integer", limit: 1} }
      let(:model_adapter) { FakeModelAdapter.lenient(types: {"age" => "integer"}) }

      before { add_cells("200.5", "5") }

      it "lists it as not fitting, with the limit it breaks and the value it is cast to" do
        expect(summary.distinct_values.incompatible).to eq(
          [incompatible_value(value: "200.5", count: 1, casted_to: 200, reason: :value_out_of_range)]
        )
        expect(summary.distinct_values.compatible).to eq([compatible_value(value: "5", count: 1, casted_to: 5)])
      end
    end

    context "with a text longer than the column allows" do
      let(:type_fields) { {type: "string", max_length: 3} }
      let(:model_adapter) { FakeModelAdapter.new }

      before { add_cells("abc", "abcdef") }

      it "lists it as not fitting, with the reason that it is too long" do
        expect(summary.distinct_values.incompatible).to eq([incompatible_value(value: "abcdef", count: 1, casted_to: "abcdef", reason: :value_too_long)])
      end

      it "lists a text inside the limit as fitting" do
        expect(summary.distinct_values.compatible).to eq([compatible_value(value: "abc", count: 1, casted_to: "abc")])
      end
    end

    context "with a value that is not a label of the enum of the column" do
      let(:type_fields) { {type: "integer", enum_values: {"draft" => 0, "placed" => 1}} }
      let(:model_adapter) { FakeModelAdapter.new }

      before { add_cells("draft", "nope") }

      it "lists it as not fitting, with the reason that it is not allowed" do
        expect(summary.distinct_values.incompatible).to eq([incompatible_value(value: "nope", count: 1, casted_to: "nope", reason: :value_not_allowed)])
      end
    end

    context "with a value that is listed again" do
      before { add_cells("x", "x") }

      it "keeps the reason it was listed with, and counts it again" do
        expect(summary.distinct_values.incompatible).to eq([incompatible_value(value: "x", count: 2, casted_to: nil, reason: :value_not_castable)])
      end
    end

    context "with a text that the adapter cannot cast" do
      let(:limits_checker) { instance_double(Pipeforge::ColumnLimitsChecker, violation_of: nil) }
      let(:mapped_column) { {source_column: "Age", position: 1, limits_checker: limits_checker} }

      before { add_cells("x") }

      it "lists it as not fitting, with the reason that it could not be read" do
        expect(summary.distinct_values.incompatible).to eq([incompatible_value(value: "x", count: 1, casted_to: nil, reason: :value_not_castable)])
      end

      it "does not ask the limits checker about it" do
        expect(limits_checker).not_to have_received(:violation_of)
      end
    end

    context "with a text that the adapter reads as nothing, as for the JSON null" do
      let(:type_fields) { {type: "json"} }
      let(:model_adapter) { instance_double(FakeModelAdapter, cast_text: Pipeforge::CastResult.new(castable: true, cast_value: nil, json_value: nil)) }

      before { add_cells("null", "null") }

      it "counts it as fitting" do
        expect(summary.type_compatibility).to eq(fits: 2, total: 2)
      end

      it "lists it as fitting, with casted_to nil because the value is nothing" do
        expect(summary.distinct_values.compatible).to eq([compatible_value(value: "null", count: 2, casted_to: nil)])
      end
    end

    context "with a text whose json value is not the text" do
      let(:type_fields) { {type: "date"} }
      let(:model_adapter) do
        instance_double(FakeModelAdapter, cast_text: Pipeforge::CastResult.new(castable: true, cast_value: Date.new(2024, 2, 3), json_value: "2024-02-03"))
      end

      before { add_cells("2024-2-3", "2024-02-03") }

      it "lists the json value as casted_to for each text, the one that is the json value itself included" do
        expect(summary.distinct_values.compatible).to eq(
          [
            compatible_value(value: "2024-2-3", count: 1, casted_to: "2024-02-03"),
            compatible_value(value: "2024-02-03", count: 1, casted_to: "2024-02-03")
          ]
        )
      end
    end

    context "with a text whose json value is false" do
      let(:type_fields) { {type: "boolean"} }
      let(:model_adapter) { instance_double(FakeModelAdapter, cast_text: Pipeforge::CastResult.new(castable: true, cast_value: false, json_value: false)) }

      before { add_cells("no") }

      it "lists false as casted_to" do
        expect(summary.distinct_values.compatible).to eq([compatible_value(value: "no", count: 1, casted_to: false)])
      end
    end

    context "with a json column whose json value is an object" do
      let(:type_fields) { {type: "json"} }
      let(:model_adapter) do
        instance_double(FakeModelAdapter, cast_text: Pipeforge::CastResult.new(castable: true, cast_value: {"a" => 1}, json_value: {"a" => 1}))
      end

      before { add_cells('{"a": 1}') }

      it "lists the object as casted_to, whichever way the text writes it" do
        expect(summary.distinct_values.compatible).to eq(
          [compatible_value(value: '{"a": 1}', count: 1, casted_to: {"a" => 1})]
        )
      end
    end

    context "with a value mapping for the column" do
      let(:value_mapping) { {"x" => "7", "30" => nil} }

      before { add_cells("30", nil, "x", "30") }

      it "measures a mapped value as the value it maps to" do
        # 30 (x2) maps to nothing and counts as empty; x maps to 7, which fits.
        expect(summary.type_compatibility).to eq(fits: 1, total: 1)
      end

      it "counts a value that maps to nothing as empty" do
        expect(summary.empty).to eq(3)
      end

      it "lists a mapped value as the value it maps to" do
        expect(summary.distinct_values.compatible).to eq([compatible_value(value: "7", count: 1, casted_to: 7)])
      end

      it "keeps the value mapping on the summary" do
        expect(summary.value_mapping).to eq("x" => "7", "30" => nil)
      end
    end

    context "with a value mapping that maps two values to one" do
      let(:value_mapping) { {"thirty" => "30"} }

      before { add_cells("30", "thirty") }

      it "lists them as one value" do
        expect(summary.distinct_values.compatible).to eq([compatible_value(value: "30", count: 2, casted_to: 30)])
      end
    end

    context "with more distinct values than the lists once held" do
      before { add_cells(*Array.new(1500) { |number| number.to_s }) }

      it "lists every one of them" do
        expect(summary.distinct_values.compatible.size).to eq(1500)
      end

      it "counts every one of them" do
        expect(summary.type_compatibility).to eq(fits: 1500, total: 1500)
      end
    end
  end

  describe "#add_row" do
    let(:model_adapter) { FakeModelAdapter.lenient(types: {"age" => "integer"}) }

    before { allow(model_adapter).to receive(:cast_text).and_call_original }

    it "casts a value once, however often it appears, for the column it is mapped to" do
      add_cells("30", "30", "30", "31")

      expect(model_adapter).to have_received(:cast_text).with(column_name: "age", text: "30").once
      expect(model_adapter).to have_received(:cast_text).with(column_name: "age", text: "31").once
    end

    it "casts a value that does not fit once, too" do
      add_cells("x", "x")

      expect(model_adapter).to have_received(:cast_text).with(column_name: "age", text: "x").once
    end

    it "does not cast empty cells" do
      add_cells(nil, "  ")

      expect(model_adapter).not_to have_received(:cast_text)
    end

    it "reads only the source column of the mapped column" do
      summary_builder.add_row(row: {"Age" => "30", "Name" => "30"})

      expect(summary_builder.summary.type_compatibility).to eq(fits: 1, total: 1)
    end

    it "counts a repeated value of the fitting list as fitting each time" do
      add_cells("30", "30", "30")

      expect(summary_builder.summary.type_compatibility).to eq(fits: 3, total: 3)
    end

    it "counts a repeated value of the other list as not fitting each time" do
      strict = FakeModelAdapter.reading(types: {"age" => "integer"})
      not_fitting = described_class.new(target_column: "age", mapped_column: mapped_column, model_adapter: strict)
      3.times { not_fitting.add_row(row: {"Age" => "x"}) }

      expect(not_fitting.summary.type_compatibility).to eq(fits: 0, total: 3)
    end
  end

  context "with two summary builders that read the same source column" do
    it "measure it once each, with that target's own type" do
      text_summary_builder = described_class.new(
        target_column: "age_text",
        mapped_column: {source_column: "Age", position: 1, type: "string"}.tap { |entry|
          entry[:limits_checker] = Pipeforge::ColumnLimitsChecker.new(type_info: entry)
        },
        model_adapter: FakeModelAdapter.reading(types: {"age" => "integer"})
      )
      ["30", nil, "x"].each do |cell|
        summary_builder.add_row(row: {"Age" => cell})
        text_summary_builder.add_row(row: {"Age" => cell})
      end

      expect(summary_builder.summary.type_compatibility).to eq(fits: 1, total: 2)
      expect(text_summary_builder.summary.type_compatibility).to eq(fits: 2, total: 2)
    end
  end
end

RSpec.describe Pipeforge::ColumnValueAnalyzer::ColumnSummary do
  describe "#to_h" do
    subject(:hash) do
      described_class.new(
        source_column: "Age",
        position: 2,
        empty: 1,
        type_compatibility: {fits: 1, total: 2},
        distinct_values: Pipeforge::ColumnValueAnalyzer::DistinctValueLists.new(
          compatible: [compatible_value(value: "30", count: 1, casted_to: 30)],
          incompatible: [incompatible_value(value: "x", count: 1, casted_to: nil, reason: :value_not_castable)]
        ),
        value_mapping: {"x" => "0"}
      ).to_h
    end

    it "is made of plain JSON types, with each list as an array of the fields of its listed values" do
      expect(hash).to eq(
        source_column: "Age",
        position: 2,
        empty: 1,
        type_compatibility: {fits: 1, total: 2},
        distinct_values: {
          compatible: [{value: "30", count: 1, casted_to: 30}],
          incompatible: [{value: "x", count: 1, casted_to: nil, reason: :value_not_castable}]
        },
        value_mapping: {"x" => "0"}
      )
    end
  end
end
