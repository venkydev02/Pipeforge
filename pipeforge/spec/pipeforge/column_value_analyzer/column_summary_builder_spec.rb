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
        expect(summary.distinct_values[:compatible].values).to eq([])
        expect(summary.distinct_values[:incompatible].values).to eq([])
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
        expect(summary.distinct_values[:compatible].values).to eq([{value: "30", count: 2}])
      end

      it "lists the values that do not fit" do
        expect(summary.distinct_values[:incompatible].values).to eq([{value: "x", count: 1}])
      end
    end

    context "with a value that the cast changes" do
      let(:model_adapter) { FakeModelAdapter.lenient(types: {"age" => "integer"}) }

      before { add_cells("30", "30", "1,000", "abc", "007") }

      it "counts every value the adapter reads as fitting" do
        expect(summary.type_compatibility).to eq(fits: 5, total: 5)
      end

      it "gives the value the cast changes a text to, and none for a text that is the loaded value" do
        expect(summary.distinct_values[:compatible].values).to eq(
          [
            {value: "30", count: 2},
            {value: "1,000", count: 1, casted_to: "1"},
            {value: "abc", count: 1, casted_to: "0"},
            {value: "007", count: 1, casted_to: "7"}
          ]
        )
      end
    end

    context "with a value that does not fit because of the cast" do
      let(:type_fields) { {type: "integer", limit: 1} }
      let(:model_adapter) { FakeModelAdapter.lenient(types: {"age" => "integer"}) }

      before { add_cells("200.5", "5") }

      it "lists it as not fitting, with the value it is cast to" do
        expect(summary.distinct_values[:incompatible].values).to eq([{value: "200.5", count: 1, casted_to: "200"}])
        expect(summary.distinct_values[:compatible].values).to eq([{value: "5", count: 1}])
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
        expect(summary.distinct_values[:compatible].values).to eq([{value: "7", count: 1}])
      end

      it "keeps the value mapping on the summary" do
        expect(summary.value_mapping).to eq("x" => "7", "30" => nil)
      end
    end

    context "with a value mapping that maps two values to one" do
      let(:value_mapping) { {"thirty" => "30"} }

      before { add_cells("30", "thirty") }

      it "lists them as one value" do
        expect(summary.distinct_values[:compatible].values).to eq([{value: "30", count: 2}])
      end
    end

    context "with more distinct values than the lists once held" do
      before { add_cells(*Array.new(1500) { |number| number.to_s }) }

      it "lists every one of them" do
        expect(summary.distinct_values[:compatible].values.size).to eq(1500)
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
  def list_of(counts)
    Pipeforge::ColumnValueAnalyzer::DistinctValues.new.tap do |list|
      counts.each { |value, count| count.times { list.record(value: value) } }
    end
  end

  describe "#to_h" do
    subject(:hash) do
      described_class.new(
        source_column: "Age",
        position: 2,
        empty: 1,
        type_compatibility: {fits: 1, total: 2},
        distinct_values: {compatible: list_of("30" => 1), incompatible: list_of("x" => 1)},
        value_mapping: {"x" => "0"}
      ).to_h
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
