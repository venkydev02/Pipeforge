# frozen_string_literal: true

# The core's engine found and used the ActiveRecord adapter, end to end, against an in-memory
# database.
RSpec.describe Pipeforge::Engine, "with the ActiveRecord adapter installed" do
  subject(:result) { engine.analyze_headers }

  let(:engine) { described_class.new(source_io: csv_io(csv), target_table: "users") }
  let(:csv) { "Email,Company,Age,Balance,Zip\nann@example.com,Acme,31,10.5,10001\n" }

  it "matches the source columns to the columns of the table, including the foreign key" do
    expect(result.matches.transform_values { |match| match[:source_column] }).to eq(
      "email" => "Email", "company_id" => "Company", "age" => "Age", "balance" => "Balance"
    )
  end

  it "lists what is left on both sides" do
    expect(result.unmatched_source_columns).to eq(%w[Zip])
    expect(result.unmatched_target_columns.map { |target| target[:name] }).to eq(%w[bio active created_at updated_at])
  end

  it "does not offer the primary key, an ignored column or a generated column" do
    offered = result.matches.keys + result.unmatched_target_columns.map { |target| target[:name] }

    expect(offered).not_to include("id", "legacy_code", "shout")
  end

  it "reports the foreign key in the metadata of its column" do
    expect(result.matches["company_id"][:metadata][:foreign_key]).to eq(
      association: "company", parent_table: "companies", required: true
    )
  end

  it "reports the model" do
    expect(result.model).to eq("AdapterSpecModels::User")
  end

  it "gives the type information of each column in its metadata" do
    expect(result.matches["age"][:metadata]).to include(type: "integer", nullable: true)
  end

  describe "#analyze_values" do
    subject(:value_result) { engine.analyze_values(mapped_columns: mapped_columns) }

    let(:csv) { "Age,Balance\n31,10.5\n99999,abc\n" }
    let(:mapped_columns) { {"Age" => {target_column: "age"}, "Balance" => {target_column: "balance"}} }

    it "measures the values against the types of the columns in the table" do
      expect(value_result.columns["Age"].type_compatibility).to eq(fits: 1, total: 2)
      expect(value_result.columns["Balance"].type_compatibility).to eq(fits: 1, total: 2)
    end

    context "with a column the engine cannot load into" do
      let(:csv) { "Id\n1\n" }
      let(:mapped_columns) { {"Id" => {target_column: "id"}} }

      it "stops with target_column_not_in_schema" do
        expect { value_result }.to raise_error(Pipeforge::InvalidMappedColumnsError) do |error|
          expect(error.codes).to eq([:target_column_not_in_schema])
        end
      end
    end
  end
end
