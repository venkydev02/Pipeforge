# frozen_string_literal: true

RSpec.describe Pipeforge::ColumnValueAnalyzer::ValueFitChecker do
  # The checker of the column's limits is built from the type fields, as the column values analyzer builds it.
  def check(text:, model_adapter:, column_name: "age", **type_fields)
    limits_checker = Pipeforge::ColumnLimitsChecker.new(type_info: type_fields)

    described_class.call(
      text: text, target_column: column_name, limits_checker: limits_checker, model_adapter: model_adapter
    )
  end

  describe ".call" do
    context "with an adapter that reads a text only when it is a value of the type of its column" do
      let(:model_adapter) { FakeModelAdapter.reading(types: {"age" => "integer"}) }

      it "fits a text the adapter reads, with no changed value" do
        expect(check(text: "30", model_adapter: model_adapter, type: "integer")).to have_attributes(fits: true, casted_to: nil)
      end

      it "does not fit a text the adapter cannot read, and gives no changed value" do
        expect(check(text: "x", model_adapter: model_adapter, type: "integer")).to have_attributes(fits: false, casted_to: nil)
      end
    end

    context "with an adapter that reads a text as nothing" do
      let(:model_adapter) { instance_double(FakeModelAdapter, cast_text: {casted: true, cast_value: nil}) }

      it "fits the text, with no changed value" do
        expect(check(text: "null", model_adapter: model_adapter, type: "integer")).to have_attributes(fits: true, casted_to: nil)
      end
    end

    context "with a column of a type that the core knows no limit for" do
      let(:model_adapter) { FakeModelAdapter.lenient(types: {"data" => "integer"}) }

      before { allow(model_adapter).to receive(:cast_text).and_call_original }

      it "casts it as for any other type, and a text the adapter reads fits" do
        outcome = check(text: "30", column_name: "data", model_adapter: model_adapter, type: "jsonb")

        expect(outcome.fits).to be(true)
        expect(model_adapter).to have_received(:cast_text).with(column_name: "data", text: "30").once
      end

      it "does not fit a text the adapter cannot read" do
        unreadable = FakeModelAdapter.new(casts: ->(column_name:, text:) {})

        expect(check(text: "x", column_name: "data", model_adapter: unreadable, type: "uuid").fits).to be(false)
      end
    end

    context "when the cast value is a structure that is not written as text" do
      let(:model_adapter) { FakeModelAdapter.new(casts: ->(column_name:, text:) { [text] }) }

      it "fits, and is not given a changed value" do
        expect(check(text: "30", model_adapter: model_adapter, type: "array")).to have_attributes(fits: true, casted_to: nil)
      end
    end

    context "with an adapter that casts leniently" do
      let(:model_adapter) { FakeModelAdapter.lenient(types: {"age" => "integer"}) }

      it "fits a text that is the loaded value, with no changed value" do
        expect(check(text: "30", model_adapter: model_adapter, type: "integer")).to have_attributes(fits: true, casted_to: nil)
      end

      it "fits a text with a thousands separator, and gives the value it is cast to" do
        expect(check(text: "1,000", model_adapter: model_adapter, type: "integer")).to have_attributes(fits: true, casted_to: "1")
      end

      it "fits a text that is not a number, and gives the value it is cast to" do
        expect(check(text: "abc", model_adapter: model_adapter, type: "integer")).to have_attributes(fits: true, casted_to: "0")
      end

      it "gives the value of a number written with leading zeros" do
        expect(check(text: "007", model_adapter: model_adapter, type: "integer")).to have_attributes(fits: true, casted_to: "7")
      end
    end

    context "when the cast value is past the limits of the column" do
      let(:model_adapter) { FakeModelAdapter.lenient(types: {"age" => "integer"}) }

      it "does not fit, and gives no changed value when the cast value is the text itself" do
        expect(check(text: "200", model_adapter: model_adapter, type: "integer", limit: 1)).to have_attributes(fits: false, casted_to: nil)
      end

      it "does not fit, and gives the cast value when the cast changed the text" do
        expect(check(text: "200.5", model_adapter: model_adapter, type: "integer", limit: 1)).to have_attributes(
          fits: false, casted_to: "200"
        )
      end

      it "fits a value inside the limits" do
        expect(check(text: "5", model_adapter: model_adapter, type: "integer", limit: 1)).to have_attributes(fits: true, casted_to: nil)
      end
    end

    context "with a decimal column" do
      let(:model_adapter) { FakeModelAdapter.lenient(types: {"fee" => "decimal"}, scales: {"fee" => 2}) }

      it "does not fit a value whose rounding adds a digit before the point, and shows the rounded value" do
        outcome = check(
          text: "999.999", column_name: "fee", model_adapter: model_adapter, type: "decimal", precision: 5, scale: 2
        )

        expect(outcome).to have_attributes(fits: false, casted_to: "1000.0")
      end

      it "writes a decimal in plain notation, rounded to the scale" do
        outcome = check(
          text: "10.505", column_name: "fee", model_adapter: model_adapter, type: "decimal", precision: 10, scale: 2
        )

        expect(outcome).to have_attributes(fits: true, casted_to: "10.51")
      end

      it "gives no changed value for a decimal that is written the way it is loaded" do
        outcome = check(
          text: "10.5", column_name: "fee", model_adapter: model_adapter, type: "decimal", precision: 10, scale: 2
        )

        expect(outcome).to have_attributes(fits: true, casted_to: nil)
      end
    end

    context "with a date column" do
      let(:model_adapter) { FakeModelAdapter.lenient(types: {"day" => "date"}) }

      it "writes a date as YYYY-MM-DD" do
        outcome = check(text: "2024-2-3", column_name: "day", model_adapter: model_adapter, type: "date")

        expect(outcome).to have_attributes(fits: true, casted_to: "2024-02-03")
      end

      it "gives no changed value for a date that is already written that way" do
        outcome = check(text: "2024-02-03", column_name: "day", model_adapter: model_adapter, type: "date")

        expect(outcome).to have_attributes(fits: true, casted_to: nil)
      end
    end
  end
end
