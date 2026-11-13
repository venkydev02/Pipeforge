# frozen_string_literal: true

RSpec.describe Pipeforge::ColumnValueAnalyzer::ColumnSummaryBuilder do
  subject(:summary_builder) do
    described_class.new(
      target_column: target_column,
      source_column: source_column,
      position: position,
      limits_checker: limits_checker,
      model_adapter: model_adapter,
      value_mapping: value_mapping
    )
  end

  # An integer column and the text 30, unless a context is about another kind of column.
  let(:target_column) { "age" }
  let(:source_column) { "Age" }
  let(:position) { 1 }
  let(:value_mapping) { {} }
  let(:cast_result) { Pipeforge::CastResult.new(castable: true, cast_value: 30, json_value: 30) }
  let(:violation) { nil }
  let(:model_adapter) { instance_double(Pipeforge::ActiveRecordModelAdapter, cast_value: cast_result) }
  let(:limits_checker) { instance_double(Pipeforge::ColumnLimitsChecker, violation_of: violation) }

  # Records one row for each cell, in order. A nil is an empty cell.
  def add_cells(*cells)
    cells.each { |cell| summary_builder.add_cell(cell: cell) }
  end

  # The summary of the column of these examples, with the source column, the position and the value mapping the builder
  # was given; what an example does not set is what a builder with no row gives.
  def expected_summary(empty: 0, compatible: [], incompatible: [], compatible_count: 0, incompatible_count: 0)
    Pipeforge::ColumnValueAnalyzer::ColumnSummary.new(
      source_column: source_column,
      position: position,
      empty: empty,
      distinct_values: Pipeforge::ColumnValueAnalyzer::DistinctValueLists.new(
        compatible: compatible,
        incompatible: incompatible,
        compatible_count: compatible_count,
        incompatible_count: incompatible_count
      ),
      value_mapping: value_mapping
    )
  end

  describe "#summary" do
    subject(:summary) { summary_builder.summary }

    shared_examples "an empty cell" do
      it "counts it as empty and not as a value" do
        expect(summary).to eq(expected_summary(empty: 1))
      end

      it "does not cast anything" do
        expect(model_adapter).not_to have_received(:cast_value)
      end
    end

    context "when no row was added" do
      it "has nothing counted or listed, and the source column, the position and an empty value mapping" do
        expect(summary).to eq(expected_summary)
      end

      context "and a value mapping was given" do
        let(:value_mapping) { {"Active" => "1"} }

        it "keeps the value mapping as given" do
          expect(summary).to eq(expected_summary)
        end
      end
    end

    context "when a cell is nil" do
      before { add_cells(nil) }

      include_examples "an empty cell"
    end

    context "when a cell is a whitespace-only text" do
      before { add_cells("   ") }

      include_examples "an empty cell"
    end

    context "when a cell is mapped to nil" do
      let(:value_mapping) { {"n/a" => nil} }

      before { add_cells("n/a") }

      include_examples "an empty cell"
    end

    context "when a cell is mapped to an empty text" do
      let(:value_mapping) { {"none" => ""} }

      before { add_cells("none") }

      include_examples "an empty cell"
    end

    context "when the rows are an empty cell, a text and an empty cell" do
      before { add_cells(nil, "30", nil) }

      it "counts two empty cells and one value" do
        expect(summary).to eq(
          expected_summary(
            empty: 2, compatible: [compatible_value(value: "30", count: 1, casted_to: 30)], compatible_count: 1
          )
        )
      end
    end

    context "when a cell is mapped to another text" do
      let(:value_mapping) { {"seven" => "7"} }
      let(:cast_result) { Pipeforge::CastResult.new(castable: true, cast_value: 7, json_value: 7) }

      before { add_cells("seven") }

      it "lists the text of the file, with the text it is mapped to" do
        expect(summary).to eq(
          expected_summary(
            compatible: [compatible_value(value: "seven", count: 1, mapping_applied: true, mapped_value: "7", casted_to: 7)],
            compatible_count: 1
          )
        )
      end

      it "casts the mapped text and not the cell" do
        expect(model_adapter).to have_received(:cast_value).with(column_name: target_column, value: "7")
      end
    end

    context "when two cells are mapped to the same text" do
      let(:value_mapping) { {"seven" => "7", "VII" => "7"} }
      let(:cast_result) { Pipeforge::CastResult.new(castable: true, cast_value: 7, json_value: 7) }

      before { add_cells("seven", "VII") }

      it "lists each text of the file, with the text they are mapped to" do
        expect(summary).to eq(
          expected_summary(
            compatible: [
              compatible_value(value: "seven", count: 1, mapping_applied: true, mapped_value: "7", casted_to: 7),
              compatible_value(value: "VII", count: 1, mapping_applied: true, mapped_value: "7", casted_to: 7)
            ],
            compatible_count: 2
          )
        )
      end
    end

    context "when a cell is mapped to a number" do
      let(:value_mapping) { {"seven" => 7} }
      let(:cast_result) { Pipeforge::CastResult.new(castable: true, cast_value: 7, json_value: 7) }

      before { add_cells("seven") }

      it "casts the number as it is" do
        expect(model_adapter).to have_received(:cast_value).with(column_name: target_column, value: 7)
      end
    end

    context "when a cell is mapped to a Hash" do
      let(:target_column) { "settings" }
      let(:source_column) { "Settings" }
      let(:value_mapping) { {"default" => {"theme" => "dark"}} }
      let(:cast_result) do
        Pipeforge::CastResult.new(castable: true, cast_value: {"theme" => "dark"}, json_value: {"theme" => "dark"})
      end

      before { add_cells("default") }

      it "lists the text of the file, with the Hash as its own mapped value" do
        expect(summary).to eq(
          expected_summary(
            compatible: [
              compatible_value(value: "default", count: 1, mapping_applied: true, mapped_value: {"theme" => "dark"}, casted_to: {"theme" => "dark"})
            ],
            compatible_count: 1
          )
        )
      end

      it "casts the Hash as it is" do
        expect(model_adapter).to have_received(:cast_value).with(column_name: target_column, value: {"theme" => "dark"})
      end
    end

    context "when a cell is mapped to false" do
      let(:target_column) { "active" }
      let(:source_column) { "Active" }
      let(:value_mapping) { {"no" => false} }
      let(:cast_result) { Pipeforge::CastResult.new(castable: true, cast_value: false, json_value: false) }

      before { add_cells("no") }

      it "does not count it as empty, and lists the text of the file with false as its mapped value" do
        expect(summary).to eq(
          expected_summary(
            compatible: [compatible_value(value: "no", count: 1, mapping_applied: true, mapped_value: false, casted_to: false)],
            compatible_count: 1
          )
        )
      end

      it "casts false as it is" do
        expect(model_adapter).to have_received(:cast_value).with(column_name: target_column, value: false)
      end
    end

    context "when a cell has no entry in the value mapping" do
      let(:value_mapping) { {"unknown" => "0"} }

      before { add_cells("30") }

      it "lists it as not mapped, with itself as its mapped value" do
        expect(summary).to eq(
          expected_summary(
            compatible: [compatible_value(value: "30", count: 1, mapping_applied: false, mapped_value: "30", casted_to: 30)],
            compatible_count: 1
          )
        )
      end

      it "casts the cell as it is" do
        expect(model_adapter).to have_received(:cast_value).with(column_name: target_column, value: "30")
      end
    end

    context "when a cell is mapped to itself" do
      let(:value_mapping) { {"30" => "30"} }

      before { add_cells("30") }

      it "lists it as mapped, though the mapped value is the cell itself" do
        expect(summary).to eq(
          expected_summary(
            compatible: [compatible_value(value: "30", count: 1, mapping_applied: true, mapped_value: "30", casted_to: 30)],
            compatible_count: 1
          )
        )
      end
    end

    context "when a new text fits" do
      # An integer column reads 1,000 as 1.
      let(:cast_result) { Pipeforge::CastResult.new(castable: true, cast_value: 1, json_value: 1) }

      before { add_cells("1,000") }

      it "counts it as fitting and lists it as a compatible value with the value it is cast to" do
        expect(summary).to eq(
          expected_summary(
            compatible: [compatible_value(value: "1,000", count: 1, casted_to: 1)], compatible_count: 1
          )
        )
      end

      it "casts the text for the target column" do
        expect(model_adapter).to have_received(:cast_value).with(column_name: target_column, value: "1,000")
      end

      it "asks the limits checker about the cast value" do
        expect(limits_checker).to have_received(:violation_of).with(value: 1)
      end
    end

    context "when a new text fits and its cast value is not its json value" do
      let(:target_column) { "price" }
      let(:source_column) { "Price" }
      # A decimal column casts 10.50 to a BigDecimal, which is a string in JSON types.
      let(:cast_result) do
        Pipeforge::CastResult.new(castable: true, cast_value: BigDecimal("10.5"), json_value: "10.5")
      end

      before { add_cells("10.50") }

      it "gives the json value as the value it is cast to, not the cast value" do
        expect(summary).to eq(
          expected_summary(
            compatible: [compatible_value(value: "10.50", count: 1, casted_to: "10.5")], compatible_count: 1
          )
        )
      end

      it "asks the limits checker about the cast value, not the json value" do
        expect(limits_checker).to have_received(:violation_of).with(value: BigDecimal("10.5"))
      end
    end

    context "when a new text breaks a limit" do
      let(:target_column) { "name" }
      let(:source_column) { "Name" }
      let(:cast_result) { Pipeforge::CastResult.new(castable: true, cast_value: "abcdef", json_value: "abcdef") }
      let(:violation) do
        Pipeforge::ColumnLimitsChecker::Violation.new(
          code: :value_too_long, detail: "the value has 6 characters, more than the 3 allowed"
        )
      end

      before { add_cells("abcdef") }

      it "lists it as an incompatible value with the code of the limit as the reason, and counts it as not fitting" do
        expect(summary).to eq(
          expected_summary(
            incompatible: [
              incompatible_value(value: "abcdef", count: 1, casted_to: "abcdef", reason: :value_too_long)
            ],
            incompatible_count: 1
          )
        )
      end

      context "and the cast value is not the json value" do
        let(:target_column) { "price" }
        let(:source_column) { "Price" }
        let(:cast_result) do
          Pipeforge::CastResult.new(castable: true, cast_value: BigDecimal("1000.5"), json_value: "1000.5")
        end
        let(:violation) do
          Pipeforge::ColumnLimitsChecker::Violation.new(
            code: :value_out_of_range, detail: "the value has more than 3 digits before the point"
          )
        end

        before { add_cells("1000.5") }

        it "gives the json value as the value it is cast to" do
          expect(summary.distinct_values.incompatible).to include(
            incompatible_value(value: "1000.5", count: 1, casted_to: "1000.5", reason: :value_out_of_range)
          )
        end
      end
    end

    context "when a new text cannot be cast" do
      let(:cast_result) { Pipeforge::CastResult::NOT_CASTABLE }

      before { add_cells("abc") }

      it "lists it as an incompatible value that is not castable and cast to nothing, and counts it as not fitting" do
        expect(summary).to eq(
          expected_summary(
            incompatible: [
              incompatible_value(value: "abc", count: 1, casted_to: nil, reason: :value_not_castable)
            ],
            incompatible_count: 1
          )
        )
      end

      it "does not ask the limits checker" do
        expect(limits_checker).not_to have_received(:violation_of)
      end
    end

    context "when a text that fits is added twice" do
      before { add_cells("30", "30") }

      it "counts it twice in its listed value and counts both as fitting" do
        expect(summary).to eq(
          expected_summary(
            compatible: [compatible_value(value: "30", count: 2, casted_to: 30)], compatible_count: 2
          )
        )
      end

      it "casts and checks the text only the first time" do
        expect(model_adapter).to have_received(:cast_value).once
        expect(limits_checker).to have_received(:violation_of).once
      end
    end

    context "when a text that does not fit is added twice" do
      let(:cast_result) { Pipeforge::CastResult.new(castable: true, cast_value: 300, json_value: 300) }
      let(:violation) do
        Pipeforge::ColumnLimitsChecker::Violation.new(
          code: :value_out_of_range, detail: "the value does not fit in 1 bytes"
        )
      end

      before { add_cells("300", "300") }

      it "counts it twice, keeps the reason and the value it is cast to of the first time, and counts none as fitting" do
        expect(summary).to eq(
          expected_summary(
            incompatible: [incompatible_value(value: "300", count: 2, casted_to: 300, reason: :value_out_of_range)],
            incompatible_count: 2
          )
        )
      end

      it "casts the text only the first time" do
        expect(model_adapter).to have_received(:cast_value).once
      end
    end

    context "when a text that fits and a text that does not fit were added" do
      before do
        allow(model_adapter).to receive(:cast_value).with(column_name: target_column, value: "abc")
          .and_return(Pipeforge::CastResult::NOT_CASTABLE)
        add_cells("30", "abc")
      end

      it "gives each text in its own list, with the two counts" do
        expect(summary).to eq(
          expected_summary(
            compatible: [compatible_value(value: "30", count: 1, casted_to: 30)],
            incompatible: [incompatible_value(value: "abc", count: 1, casted_to: nil, reason: :value_not_castable)],
            compatible_count: 1,
            incompatible_count: 1
          )
        )
      end
    end
  end

  describe Pipeforge::ColumnValueAnalyzer::ColumnSummary do
    describe "#to_h" do
      subject(:plain_summary) { column_summary.to_h }

      let(:column_summary) do
        described_class.new(
          source_column: "Age",
          position: 1,
          empty: 2,
          distinct_values: Pipeforge::ColumnValueAnalyzer::DistinctValueLists.new(
            compatible: [compatible_value(value: "30", count: 1, casted_to: 30)],
            incompatible: [incompatible_value(value: "abc", count: 1, casted_to: nil, reason: :value_not_castable)],
            compatible_count: 1,
            incompatible_count: 1
          ),
          value_mapping: {"n/a" => "0"}
        )
      end

      it "writes the summary in plain JSON types, each listed value as a hash with its fields" do
        expect(plain_summary).to eq(
          source_column: "Age",
          position: 1,
          empty: 2,
          distinct_values: {
            compatible: [{value: "30", count: 1, mapping_applied: false, mapped_value: "30", casted_to: 30}],
            incompatible: [
              {
                value: "abc", count: 1, mapping_applied: false, mapped_value: "abc", casted_to: nil,
                reason: :value_not_castable
              }
            ],
            compatible_count: 1,
            incompatible_count: 1
          },
          value_mapping: {"n/a" => "0"}
        )
      end
    end
  end
end
