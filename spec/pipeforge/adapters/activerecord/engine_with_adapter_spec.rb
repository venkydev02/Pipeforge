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

    it "counts a text that the model reads leniently as fitting, and gives the value the database would receive" do
      expect(value_result.columns["balance"].type_compatibility).to eq(fits: 2, total: 2)

      entries = value_result.columns["balance"].distinct_values.compatible
      # A number on SQLite and a text on PostgreSQL, so it is compared as text.
      expect(entries.first).to have_attributes(value: "10.5", count: 1, casted_to: satisfy { |casted_to| casted_to.to_s == "10.5" })
      expect(entries.last).to have_attributes(value: "abc", count: 1, casted_to: satisfy { |casted_to| casted_to.to_s == "0.0" })
    end

    context "with texts that the model changes when it casts them" do
      let(:csv) { "Email,Company,Age,Balance\nann@example.com,1,\"1,000\",\"1,234.50\"\nbob@example.com,2,31,10.50\n" }

      it "gives the value the database would receive for each text, the text itself included" do
        expect(value_result.columns["age"].distinct_values.compatible).to contain_exactly(
          compatible_value(value: "31", count: 1, casted_to: 31), compatible_value(value: "1,000", count: 1, casted_to: 1)
        )
      end

      it "gives the decimal the database would receive, without the zeros the text had" do
        entries = value_result.columns["balance"].distinct_values.compatible
        # A number on SQLite and a text on PostgreSQL, so it is compared as text.
        entries_with_text = entries.map { |entry| entry.with(casted_to: entry.casted_to.to_s) }

        expect(entries_with_text).to contain_exactly(
          compatible_value(value: "1,234.50", count: 1, casted_to: "1.0"),
          compatible_value(value: "10.50", count: 1, casted_to: "10.5")
        )
      end
    end

    context "with a number outside the range of its column, written in a way the cast changes" do
      let(:csv) { "Email,Company,Age,Balance\nann@example.com,1,\"99999.5\",10\n" }

      it "lists it as not fitting, with the integer it was cast to" do
        expect(value_result.columns["age"].distinct_values.incompatible).to eq(
          [incompatible_value(value: "99999.5", count: 1, casted_to: 99_999, reason: :value_out_of_range)]
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

      it "lists a value that is not a label or a stored value as not fitting, with the reason that it is not allowed" do
        expect(value_result.columns["status"].distinct_values.incompatible).to eq(
          [incompatible_value(value: "nope", count: 1, casted_to: "nope", reason: :value_not_allowed)]
        )
      end
    end

    context "with a date column of the model" do
      let(:engine) { described_class.new(source_io: csv_io(csv), target_model: "AdapterSpecModels::Event") }
      let(:csv) { "Day\n2024-02-03\n2024-2-3\n\"Feb 3, 2024\"\n2024-02-30\ngarbage\n" }
      let(:mapped_columns) { {"starts_on" => {source_column: "Day"}} }

      it "counts the formats that the model reads as fitting, and the days it cannot cast as not" do
        expect(value_result.columns["starts_on"].type_compatibility).to eq(fits: 3, total: 5)
      end

      it "lists the texts that the model cannot cast, for a value mapping to fix" do
        incompatible = value_result.columns["starts_on"].distinct_values.incompatible.map(&:value)

        expect(incompatible).to contain_exactly("2024-02-30", "garbage")
      end

      it "gives the reason that the model cannot cast them" do
        reasons = value_result.columns["starts_on"].distinct_values.incompatible.map(&:reason)

        expect(reasons).to eq(%i[value_not_castable value_not_castable])
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
          value_result.columns[target_column].distinct_values.compatible.map(&:value)
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

    context "with a json column" do
      let(:engine) { described_class.new(source_io: csv_io(csv), target_model: "AdapterSpecModels::Profile") }
      let(:csv) { "Name,Settings\nann,\"{\"\"theme\"\":\"\"dark\"\"}\"\nbob,{oops\ncat,null\ndee,\n" }
      let(:mapped_columns) { {"settings" => {source_column: "Settings"}} }

      it "counts a text that describes JSON, and the JSON null, as fitting, and one that does not as not fitting" do
        expect(value_result.columns["settings"].type_compatibility).to eq(fits: 2, total: 3)
      end

      it "lists the JSON null as a value that fits" do
        compatible = value_result.columns["settings"].distinct_values.compatible.map(&:value)

        expect(compatible).to include("null")
      end

      it "gives the JSON null casted_to nil, because the database receives NULL" do
        compatible = value_result.columns["settings"].distinct_values.compatible

        expect(compatible).to include(compatible_value(value: "null", count: 1, casted_to: nil))
      end

      it "counts an empty cell as empty, and not as a value" do
        expect(value_result.columns["settings"].empty).to eq(1)
      end

      it "lists the text that is not JSON, for a value mapping to fix" do
        incompatible = value_result.columns["settings"].distinct_values.incompatible.map(&:value)

        expect(incompatible).to eq(["{oops"])
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
