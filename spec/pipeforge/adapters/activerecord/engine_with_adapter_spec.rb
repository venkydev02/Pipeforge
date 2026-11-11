# frozen_string_literal: true

# The core's engine found and used the ActiveRecord adapter, end to end, against an in-memory
# database.
RSpec.describe Pipeforge::Engine, "with the ActiveRecord adapter installed" do
  subject(:result) { engine.analyze_headers }

  let(:engine) { described_class.new(source_io: csv_io(csv), target_model: "AdapterSpecModels::User") }
  let(:csv) { "Email,Company,Age,Balance,Zip\nann@example.com,Acme,31,10.5,10001\n" }

  # The match of a target column in the header result.
  def match_for(target_column:)
    result.matches.find { |match| match[:target_column] == target_column }
  end

  it "matches the source columns to the columns of the table, including the foreign key" do
    expect(result.matches.map { |match| [match[:target_column], match[:source_column]] }).to eq(
      [["email", "Email"], ["age", "Age"], ["balance", "Balance"], ["company_id", "Company"]]
    )
  end

  it "lists what is left on both sides" do
    expect(result.unmatched_source_columns).to eq(%w[Zip])
    expect(result.unmatched_target_columns.map { |target| target[:target_column] }).to eq(%w[bio active created_at updated_at])
  end

  it "does not offer the primary key, an ignored column or a generated column" do
    offered = result.matches.map { |match| match[:target_column] } + result.unmatched_target_columns.map { |target| target[:target_column] }

    expect(offered).not_to include("id", "legacy_code", "shout")
  end

  it "reports the foreign key in the metadata of its column" do
    expect(match_for(target_column: "company_id")[:metadata][:foreign_key]).to eq(
      association: "company", parent_table: "companies"
    )
  end

  it "reports the model" do
    expect(result.model).to eq("AdapterSpecModels::User")
  end

  context "when the table has an array column", :postgresql_only do
    let(:engine) { described_class.new(source_io: csv_io(csv), target_model: "AdapterSpecModels::Playlist") }
    let(:csv) { "Title,Track ids\nmix,\"{1,2}\"\n" }

    it "refuses a mapping to the array column, as a column that cannot be loaded" do
      expect { engine.analyze_column_values(mapped_columns: {"track_ids" => {source_column: "Track ids"}}) }
        .to raise_error(Pipeforge::InvalidMappedColumnsError) do |error|
          expect(error.errors.map { |entry| entry[:code] }).to eq([:target_column_not_in_schema])
        end
    end

    it "loads the other columns of the table" do
      totals = engine.run(mode: :dry_run, mapped_columns: {"title" => {source_column: "Title"}}) { |chunk| }

      expect(totals).to have_attributes(processed_rows_count: 1, valid_rows_count: 1, failed_rows_count: 0)
    end
  end

  it "gives the type information of each column in its metadata" do
    expect(match_for(target_column: "age")[:metadata]).to include(type: "integer", required: false)
  end

  describe "#analyze_column_values" do
    subject(:value_result) { engine.analyze_column_values(mapped_columns: mapped_columns) }

    let(:csv) { "Email,Company,Age,Balance\nann@example.com,1,31,10.5\nbob@example.com,2,99999,abc\n" }
    let(:required_columns) { {"email" => {source_column: "Email"}} }
    let(:mapped_columns) do
      required_columns.merge(
        "company_id" => {source_column: "Company"}, "age" => {source_column: "Age"}, "balance" => {source_column: "Balance"}
      )
    end

    it "measures the values against the limits of the columns in the table" do
      expect(value_result.columns["age"].type_compatibility).to eq(fits: 1, total: 2)
    end

    it "counts a text that the model reads leniently as fitting, and gives the value it would load" do
      expect(value_result.columns["balance"].type_compatibility).to eq(fits: 2, total: 2)
      expect(value_result.columns["balance"].distinct_values[:compatible].values).to eq(
        [{value: "10.5", count: 1}, {value: "abc", count: 1, casted_to: "0.0"}]
      )
    end

    context "with texts that the model changes when it casts them" do
      let(:csv) { "Email,Company,Age,Balance\nann@example.com,1,\"1,000\",\"1,234.50\"\nbob@example.com,2,31,10.50\n" }

      it "gives the value each text would load as, and none for a text that is the loaded value" do
        expect(value_result.columns["age"].distinct_values[:compatible].values).to contain_exactly(
          {value: "31", count: 1}, {value: "1,000", count: 1, casted_to: "1"}
        )
      end

      it "writes a decimal in plain notation, and shows the zeros the text had as a change" do
        expect(value_result.columns["balance"].distinct_values[:compatible].values).to contain_exactly(
          {value: "1,234.50", count: 1, casted_to: "1.0"}, {value: "10.50", count: 1, casted_to: "10.5"}
        )
      end
    end

    it "does not ask for the timestamps, which the model fills" do
      expect { value_result }.not_to raise_error
    end

    context "with an enum column of the model" do
      let(:engine) { described_class.new(source_io: csv_io(csv), target_model: "AdapterSpecModels::Shipment") }
      let(:csv) { "Status,Priority\ndraft,low\n1,high\nnope,9\n" }
      let(:mapped_columns) do
        {"status" => {source_column: "Status"}, "priority" => {source_column: "Priority"}}
      end

      it "counts the labels and the stored values of the enum as fitting" do
        expect(value_result.columns["status"].type_compatibility).to eq(fits: 2, total: 3)
        expect(value_result.columns["priority"].type_compatibility).to eq(fits: 2, total: 3)
      end
    end

    context "with a date column of the model" do
      let(:engine) { described_class.new(source_io: csv_io(csv), target_model: "AdapterSpecModels::Event") }
      let(:csv) { "Day\n2024-02-03\n2024-2-3\n\"Feb 3, 2024\"\n2024-02-30\ngarbage\n" }
      let(:mapped_columns) { {"starts_on" => {source_column: "Day"}} }

      it "counts the formats that the model reads as fitting, and the days it cannot read as not" do
        expect(value_result.columns["starts_on"].type_compatibility).to eq(fits: 3, total: 5)
      end

      it "lists the texts that the model cannot read, for a value mapping to fix" do
        incompatible = value_result.columns["starts_on"].distinct_values[:incompatible].values.map { |entry| entry[:value] }

        expect(incompatible).to contain_exactly("2024-02-30", "garbage")
      end
    end

    context "with an unsigned integer attribute of the model" do
      let(:engine) { described_class.new(source_io: csv_io(csv), target_model: "AdapterSpecModels::Counter") }
      let(:csv) { "Hits,Misses\n40000,40000\n-1,-1\n" }
      let(:mapped_columns) do
        {"hits" => {source_column: "Hits"}, "misses" => {source_column: "Misses"}}
      end

      it "measures a value against the unsigned range of that column and the signed range of the other" do
        compatible_values = lambda do |target_column|
          value_result.columns[target_column].distinct_values[:compatible].values.map { |entry| entry[:value] }
        end

        expect(compatible_values.call("hits")).to eq(%w[40000])
        expect(compatible_values.call("misses")).to eq(%w[-1])
      end
    end

    context "with a bigint column and an integer column declared with no size, given 3000000000" do
      let(:engine) { described_class.new(source_io: csv_io(csv), target_model: "AdapterSpecModels::Quantity") }
      let(:csv) { "Plain,Big\n3000000000,3000000000\n" }
      let(:mapped_columns) do
        {"plain_count" => {source_column: "Plain"}, "big_count" => {source_column: "Big"}}
      end

      it "counts the value as fitting the bigint column" do
        expect(value_result.columns["big_count"].type_compatibility).to eq(fits: 1, total: 1)
      end

      context "and the database is SQLite" do
        it "counts the value as fitting the integer column, which SQLite holds in 8 bytes", :sqlite_only do
          expect(value_result.columns["plain_count"].type_compatibility).to eq(fits: 1, total: 1)
        end
      end

      context "and the database is PostgreSQL" do
        it "counts the value as not fitting the integer column, which holds 4 bytes", :postgresql_only do
          expect(value_result.columns["plain_count"].type_compatibility).to eq(fits: 0, total: 1)
        end
      end
    end

    context "with a column the engine cannot load into" do
      let(:mapped_columns) { required_columns.merge("id" => {source_column: "Age"}) }

      it "stops with target_column_not_in_schema" do
        expect { value_result }.to raise_error(Pipeforge::InvalidMappedColumnsError) do |error|
          expect(error.codes).to eq([:target_column_not_in_schema])
        end
      end
    end

    context "when the required columns are not mapped" do
      let(:mapped_columns) { {"age" => {source_column: "Age"}} }

      it "asks for the NOT NULL column without a default, and for nothing else" do
        expect { value_result }.to raise_error(Pipeforge::InvalidMappedColumnsError) do |error|
          expect(error.errors.map { |entry| entry.slice(:code, :target_column) }).to eq(
            [{code: :required_column_unmapped, target_column: "email"}]
          )
        end
      end
    end
  end
end
