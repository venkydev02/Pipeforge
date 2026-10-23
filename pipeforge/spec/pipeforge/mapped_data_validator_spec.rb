# frozen_string_literal: true

RSpec.describe Pipeforge::MappedDataValidator do
  subject(:validator) do
    described_class.new(
      source_header_names: %w[Mail Age Zip], target_column_names: %w[email age], target_table: "users"
    )
  end

  let(:mapped_columns) { {"Mail" => {target_column: "email"}, "Age" => {target_column: "age"}} }

  # The codes and source columns of the entries the validator raises with.
  def raised_entries
    validator.call(mapped_columns: mapped_columns)
  rescue Pipeforge::InvalidMappedColumnsError => error
    error.errors.map { |entry| entry.slice(:code, :source_column) }
  end

  describe "#call" do
    context "when every mapped column fits the file and the schema" do
      it "raises nothing" do
        expect { validator.call(mapped_columns: mapped_columns) }.not_to raise_error
      end
    end

    context "when nothing is mapped" do
      let(:mapped_columns) { {} }

      it "raises nothing" do
        expect { validator.call(mapped_columns: mapped_columns) }.not_to raise_error
      end
    end

    context "when a mapped source column is not in the file" do
      let(:mapped_columns) { {"Nope" => {target_column: "email"}} }

      it "gives mapped_column_not_in_file with the source column" do
        expect(raised_entries).to eq([{code: :mapped_column_not_in_file, source_column: "Nope"}])
      end
    end

    context "when a mapped column has no target column" do
      let(:mapped_columns) { {"Mail" => {}} }

      it "gives column_missing_target_column with the source column" do
        expect(raised_entries).to eq([{code: :column_missing_target_column, source_column: "Mail"}])
      end
    end

    context "when the target column is not in the schema" do
      let(:mapped_columns) { {"Zip" => {target_column: "zip"}} }

      it "gives target_column_not_in_schema with the source column" do
        expect(raised_entries).to eq([{code: :target_column_not_in_schema, source_column: "Zip"}])
      end

      it "names the target column and the table in the entry" do
        expect { validator.call(mapped_columns: mapped_columns) }.to raise_error(
          Pipeforge::InvalidMappedColumnsError
        ) do |error|
          expect(error.errors.first).to include(target_column: "zip", table: "users")
        end
      end
    end

    context "when a mapped column carries a value mapping" do
      let(:mapped_columns) { {"Mail" => {target_column: "email", value_mapping: {"N/A" => nil}}} }

      it "raises nothing" do
        expect { validator.call(mapped_columns: mapped_columns) }.not_to raise_error
      end
    end

    context "when several things are wrong at once" do
      let(:mapped_columns) { {"Nope" => {}, "Zip" => {target_column: "zip"}} }

      it "lists every mistake in order" do
        expect(raised_entries).to eq(
          [
            {code: :mapped_column_not_in_file, source_column: "Nope"},
            {code: :column_missing_target_column, source_column: "Nope"},
            {code: :target_column_not_in_schema, source_column: "Zip"}
          ]
        )
      end
    end
  end
end
