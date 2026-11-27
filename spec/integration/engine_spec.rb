# frozen_string_literal: true

RSpec.describe Pipeforge::Engine, "migrating a CSV file into the table of a model" do
  let(:engine) { described_class.new(source_io: source_file, target_model_name: imported_user.name) }
  let(:source_file) { File.open(csv_file(source_text)) }
  let(:company) { AdapterSpecModels::Company.create!(name: "Acme") }
  let(:imported_user) do
    define_model(
      name: "ImportedUser",
      columns: ->(table) {
        table.string :email
        table.integer :age
        table.references :company, foreign_key: true
      }
    ) do
      belongs_to :company, class_name: "AdapterSpecModels::Company", optional: true
      validates :email, presence: true, uniqueness: true
    end
  end
  # Row 3 has an Age too large for the column, row 4 a company with no row, row 5 the email of row 1.
  let(:source_text) do
    <<~CSV
      Email,Age,Company Id,Notes
      ann@example.com,31,#{company.id},first
      bob@example.com,N/A,#{company.id},second
      cy@example.com,3000000000,#{company.id},third
      dee@example.com,28,999999,fourth
      ann@example.com,52,#{company.id},fifth
      eve@example.com,45,#{company.id},sixth
    CSV
  end
  let(:mapped_columns) do
    {
      email: {source_column_name: "Email"},
      age: {source_column_name: "Age", value_mapping: {"N/A" => nil}},
      company_id: {source_column_name: "Company Id"}
    }
  end
  let(:chunk_results) { [] }
  let(:failed_codes_by_row_number) do
    codes_by_row_number = {}

    chunk_results.each do |chunk_result|
      chunk_result.failed_rows.each do |failed_row|
        codes_by_row_number[failed_row.row_number] = failed_row.errors.map(&:code)
      end
    end

    codes_by_row_number
  end

  after { source_file.close }

  def run_collecting_chunk_results(mode:)
    engine.run(mode: mode, mapped_columns: mapped_columns) { |chunk_result| chunk_results << chunk_result }
  end

  context "when analyze_headers is called" do
    subject(:header_analysis) { engine.analyze_headers }

    it "matches each target column to its source column" do
      matched_column_names = header_analysis.matches.map { |match| match.values_at(:target_column_name, :source_column_name) }

      expect(matched_column_names).to eq([["email", "Email"], ["age", "Age"], ["company_id", "Company Id"]])
    end

    it "lists Notes in unmatched_source_column_names" do
      expect(header_analysis.unmatched_source_column_names).to eq(["Notes"])
    end
  end

  context "when analyze_column_values is called with a value_mapping of N/A to nil" do
    subject!(:value_analysis) { engine.analyze_column_values(mapped_columns: mapped_columns) }

    let(:age_summary) { value_analysis.column_summaries.fetch("age") }

    it "lists the Age too large for the column as incompatible" do
      expect(age_summary.distinct_values.incompatible.map(&:value)).to eq(["3000000000"])
    end

    it "counts the N/A of Age as empty" do
      expect(age_summary.empty).to eq(1)
    end

    it "writes no row" do
      expect(imported_user.count).to eq(0)
    end
  end

  context "when run is called with mode :run" do
    subject!(:run_result) { run_collecting_chunk_results(mode: :run) }

    it "keeps the rows with no error in the table, with their cast values" do
      expect(imported_user.pluck(:email, :age, :company_id)).to contain_exactly(
        ["ann@example.com", 31, company.id],
        ["bob@example.com", nil, company.id],
        ["eve@example.com", 45, company.id]
      )
    end

    it "counts the written rows and the failed rows in the totals" do
      expect(run_result).to eq(
        Pipeforge::RunProcessor::RunResult.new(processed_rows_count: 6, valid_rows_count: 3, failed_rows_count: 3)
      )
    end

    it "gives the block the failed rows with their row numbers" do
      expect(failed_codes_by_row_number.keys).to eq([3, 4, 5])
    end

    it "gives the block value_out_of_range for the Age too large for the column" do
      expect(failed_codes_by_row_number[3]).to eq([:value_out_of_range])
    end

    it "gives the block parent_missing for the company with no row" do
      expect(failed_codes_by_row_number[4]).to eq([:parent_missing])
    end

    it "gives the block value_not_unique for the email used twice" do
      expect(failed_codes_by_row_number[5]).to eq([:value_not_unique])
    end
  end

  context "when run is called with mode :dry_run" do
    before { run_collecting_chunk_results(mode: :dry_run) }

    it "leaves the table with no row" do
      expect(imported_user.count).to eq(0)
    end

    it "gives the block the same row numbers and codes as mode :run" do
      expect(failed_codes_by_row_number).to eq(
        3 => [:value_out_of_range], 4 => [:parent_missing], 5 => [:value_not_unique]
      )
    end
  end

  context "when an earlier run with chunk_size 2 stopped after its first chunk" do
    let!(:last_row_number_of_earlier_run) do
      engine.run(mode: :run, mapped_columns: mapped_columns, chunk_size: 2) do |chunk_result|
        break chunk_result.last_row_number
      end
    end

    context "and run is called with that last row number as offset" do
      subject!(:run_result) do
        engine.run(mode: :run, mapped_columns: mapped_columns, offset: last_row_number_of_earlier_run, chunk_size: 2) do |chunk_result|
          chunk_results << chunk_result
        end
      end

      it "processes only the rows after that row, two in each chunk" do
        row_number_ranges = chunk_results.map { |chunk_result| [chunk_result.first_row_number, chunk_result.last_row_number] }

        expect(row_number_ranges).to eq([[3, 4], [5, 6]])
      end

      it "counts only the rows after that row in processed_rows_count" do
        expect(run_result.processed_rows_count).to eq(4)
      end
    end
  end

  context "when the three stages are called on one engine" do
    let!(:header_analysis) { engine.analyze_headers }
    let!(:value_analysis) { engine.analyze_column_values(mapped_columns: mapped_columns) }
    let!(:run_result) { engine.run(mode: :run, mapped_columns: mapped_columns) }

    it "gives analyze_headers a match for each target column" do
      expect(header_analysis.matches.size).to eq(3)
    end

    it "gives analyze_column_values every row of the file" do
      expect(value_analysis.row_count).to eq(6)
    end

    it "gives run every row of the file" do
      expect(run_result.processed_rows_count).to eq(6)
    end
  end
end
