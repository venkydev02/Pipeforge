# frozen_string_literal: true

RSpec.describe Pipeforge::MappedDataValidator do
  subject(:validator) do
    described_class.new(
      source_header_names: %w[Mail Age Zip],
      target_column_names: %w[email age name],
      required_target_column_names: required_target_column_names,
      target_table: "users"
    )
  end

  let(:required_target_column_names) { %w[email] }
  let(:mapped_columns) { {"email" => {source_column: "Mail"}, "age" => {source_column: "Age"}} }

  # The codes and the columns of the entries the validator raises with.
  def raised_entries
    validator.call(mapped_columns: mapped_columns)
  rescue Pipeforge::InvalidMappedColumnsError => error
    error.errors.map { |entry| entry.slice(:code, :target_column, :source_column) }
  end

  describe "#call" do
    context "when every mapped column fits the file and the schema and the required column is mapped" do
      it "raises nothing" do
        expect { validator.call(mapped_columns: mapped_columns) }.not_to raise_error
      end
    end

    context "when a mapped column carries a value mapping" do
      let(:mapped_columns) { {"email" => {source_column: "Mail", value_mapping: {"N/A" => nil}}} }

      it "raises nothing" do
        expect { validator.call(mapped_columns: mapped_columns) }.not_to raise_error
      end
    end

    context "when a target column is not in the schema" do
      let(:mapped_columns) { {"email" => {source_column: "Mail"}, "nowhere" => {source_column: "Zip"}} }

      it "gives target_column_not_in_schema with the target and source columns" do
        expect(raised_entries).to eq(
          [{code: :target_column_not_in_schema, target_column: "nowhere", source_column: "Zip"}]
        )
      end

      it "names the table in the entry" do
        expect { validator.call(mapped_columns: mapped_columns) }.to raise_error(
          Pipeforge::InvalidMappedColumnsError
        ) do |error|
          expect(error.errors.first).to include(table: "users")
        end
      end
    end

    context "when an entry has no source column" do
      let(:mapped_columns) { {"email" => {value_mapping: {}}} }

      it "gives column_missing_source_column with the target column" do
        expect(raised_entries).to eq([{code: :column_missing_source_column, target_column: "email"}])
      end
    end

    context "when the source column is not in the file" do
      let(:mapped_columns) { {"email" => {source_column: "Nope"}} }

      it "gives mapped_column_not_in_file with the target and source columns" do
        expect(raised_entries).to eq(
          [{code: :mapped_column_not_in_file, target_column: "email", source_column: "Nope"}]
        )
      end
    end

    context "when a required target column has no entry" do
      let(:mapped_columns) { {"age" => {source_column: "Age"}} }

      it "gives required_column_unmapped with the target column" do
        expect(raised_entries).to eq([{code: :required_column_unmapped, target_column: "email"}])
      end
    end

    context "when several required target columns have no entry" do
      let(:required_target_column_names) { %w[email name] }
      let(:mapped_columns) { {"age" => {source_column: "Age"}} }

      it "gives one entry for each, in the order of the required columns" do
        expect(raised_entries).to eq(
          [
            {code: :required_column_unmapped, target_column: "email"},
            {code: :required_column_unmapped, target_column: "name"}
          ]
        )
      end
    end

    context "when a required target column has an entry that names no source column" do
      let(:mapped_columns) { {"email" => {}} }

      it "reports the missing source column only, not also an unmapped column" do
        expect(raised_entries).to eq([{code: :column_missing_source_column, target_column: "email"}])
      end
    end

    context "when the mapped columns are not a Hash" do
      let(:mapped_columns) { [["email", {source_column: "Mail"}]] }

      it "gives mapped_columns_not_name_value_entries alone" do
        expect(raised_entries).to eq([{code: :mapped_columns_not_name_value_entries}])
      end
    end

    context "when an entry is nil" do
      let(:mapped_columns) { {"email" => nil, "age" => {source_column: "Age"}} }

      it "gives mapped_column_not_name_value_entries with the target column" do
        expect(raised_entries).to eq([{code: :mapped_column_not_name_value_entries, target_column: "email"}])
      end
    end

    context "when an entry is a string" do
      let(:mapped_columns) { {"email" => "Mail"} }

      it "gives mapped_column_not_name_value_entries, and no follow-on error for that entry" do
        expect(raised_entries).to eq([{code: :mapped_column_not_name_value_entries, target_column: "email"}])
      end
    end

    context "when a bad entry sits next to other mistakes" do
      let(:mapped_columns) { {"email" => nil, "age" => {source_column: "Nope"}} }

      it "still reports the other mistakes" do
        expect(raised_entries).to eq(
          [
            {code: :mapped_column_not_name_value_entries, target_column: "email"},
            {code: :mapped_column_not_in_file, target_column: "age", source_column: "Nope"}
          ]
        )
      end
    end

    context "when the value mapping is a list" do
      let(:mapped_columns) { {"email" => {source_column: "Mail", value_mapping: ["yes"]}} }

      it "gives value_mapping_not_name_value_entries with the target column" do
        expect(raised_entries).to eq([{code: :value_mapping_not_name_value_entries, target_column: "email"}])
      end
    end

    context "when the value mapping is a string" do
      let(:mapped_columns) { {"email" => {source_column: "Mail", value_mapping: "yes"}} }

      it "gives value_mapping_not_name_value_entries with the target column" do
        expect(raised_entries).to eq([{code: :value_mapping_not_name_value_entries, target_column: "email"}])
      end
    end

    context "when the value mapping is nil" do
      let(:mapped_columns) { {"email" => {source_column: "Mail", value_mapping: nil}} }

      it "gives value_mapping_not_name_value_entries with the target column" do
        expect(raised_entries).to eq([{code: :value_mapping_not_name_value_entries, target_column: "email"}])
      end
    end

    context "when the value mapping is left out" do
      let(:mapped_columns) { {"email" => {source_column: "Mail"}} }

      it "raises nothing, because the value mapping is optional" do
        expect { validator.call(mapped_columns: mapped_columns) }.not_to raise_error
      end
    end

    context "when the value mapping maps to nil, a blank, false and a number" do
      let(:mapped_columns) do
        {"email" => {source_column: "Mail", value_mapping: {"N/A" => nil, "-" => "", "no" => false, "one" => 1}}}
      end

      it "raises nothing, because its keys and values are not checked" do
        expect { validator.call(mapped_columns: mapped_columns) }.not_to raise_error
      end
    end

    context "when no target column is required" do
      let(:required_target_column_names) { [] }
      let(:mapped_columns) { {} }

      it "accepts nothing being mapped" do
        expect { validator.call(mapped_columns: mapped_columns) }.not_to raise_error
      end
    end

    context "when one source column is mapped to two target columns" do
      let(:mapped_columns) { {"email" => {source_column: "Mail"}, "name" => {source_column: "Mail"}} }

      it "raises nothing, because the consumer may do that on purpose" do
        expect { validator.call(mapped_columns: mapped_columns) }.not_to raise_error
      end
    end

    context "when several things are wrong at once" do
      let(:mapped_columns) { {"nowhere" => {source_column: "Nope"}, "age" => {}} }

      it "lists every mistake in order: each entry first, then the required columns" do
        expect(raised_entries).to eq(
          [
            {code: :target_column_not_in_schema, target_column: "nowhere", source_column: "Nope"},
            {code: :mapped_column_not_in_file, target_column: "nowhere", source_column: "Nope"},
            {code: :column_missing_source_column, target_column: "age"},
            {code: :required_column_unmapped, target_column: "email"}
          ]
        )
      end
    end
  end
end
