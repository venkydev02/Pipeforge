# frozen_string_literal: true

RSpec.describe Pipeforge::RowTransformer do
  subject(:transformer) { described_class.new(mapped_columns: mapped_columns) }

  let(:mapped_columns) do
    {
      "email" => {source_column: "Mail"},
      "name" => {source_column: "Name"}
    }
  end
  let(:row) { {"Mail" => "ann@example.com", "Name" => "Ann", "Zip" => "10001"} }

  describe "#result_of_row" do
    subject(:values) { transformer.result_of_row(row: row) }

    it "reads each target column from its source column" do
      expect(values).to eq("email" => "ann@example.com", "name" => "Ann")
    end

    it "leaves out the source columns that no target column uses" do
      expect(values.keys).not_to include("Zip")
    end

    context "when two target columns read the same source column" do
      let(:mapped_columns) do
        {"first_name" => {source_column: "Name"}, "display_name" => {source_column: "Name"}}
      end

      it "gives each of them the value" do
        expect(values).to eq("first_name" => "Ann", "display_name" => "Ann")
      end
    end

    context "with an empty cell" do
      let(:row) { {"Mail" => nil, "Name" => "Ann"} }

      it "gives nil" do
        expect(values["email"]).to be_nil
      end
    end

    context "with a value mapping" do
      let(:mapped_columns) do
        {"name" => {source_column: "Name", value_mapping: {"Ann" => "Anna", "N/A" => nil, "Bob" => "   ", "Cy" => false}}}
      end

      it "gives the value the mapping maps to" do
        expect(values["name"]).to eq("Anna")
      end

      context "when the value is not in the mapping" do
        let(:row) { {"Name" => "Dee"} }

        it "keeps the value" do
          expect(values["name"]).to eq("Dee")
        end
      end

      context "when the value maps to nil" do
        let(:row) { {"Name" => "N/A"} }

        it "gives nil" do
          expect(values["name"]).to be_nil
        end
      end

      context "when the value maps to blank text" do
        let(:row) { {"Name" => "Bob"} }

        it "gives nil" do
          expect(values["name"]).to be_nil
        end
      end

      context "when the value maps to false" do
        let(:row) { {"Name" => "Cy"} }

        it "keeps false, which is not empty" do
          expect(values["name"]).to be(false)
        end
      end
    end
  end

  # The column values stage and the run apply the value mapping separately, and must agree on what each
  # value becomes and which values are empty.
  describe "agreement with the column values analysis" do
    let(:rows) do
      [
        {"Status" => "yes"}, {"Status" => "N/A"}, {"Status" => nil}, {"Status" => "maybe"}, {"Status" => "yes"},
        {"Status" => "blank"}
      ]
    end
    let(:value_mapping) { {"yes" => "Y", "N/A" => nil, "blank" => "  "} }
    let(:mapped_columns) { {"status" => {source_column: "Status", value_mapping: value_mapping}} }
    let(:column_summary) do
      analyzer_columns = {
        "status" => mapped_columns["status"].merge(
          position: 0,
          limits_checker: Pipeforge::ColumnLimitsChecker.new(type_info: {type: "string"})
        )
      }

      summary_builder = Pipeforge::ColumnValueAnalyzer::ColumnSummaryBuilder.new(
        target_column: "status", mapped_column: analyzer_columns["status"], model_adapter: FakeModelAdapter.new
      )
      rows.each { |row| summary_builder.add_row(row: row) }

      summary_builder.summary
    end
    let(:loaded_values) { rows.map { |row| transformer.result_of_row(row: row)["status"] } }

    it "counts the same empty values" do
      expect(column_summary.empty).to eq(loaded_values.count(nil))
    end

    it "lists the same values to load" do
      listed_values = column_summary.distinct_values[:compatible].values.map { |entry| entry[:value] }

      expect(listed_values).to match_array(loaded_values.compact.uniq)
    end
  end
end
