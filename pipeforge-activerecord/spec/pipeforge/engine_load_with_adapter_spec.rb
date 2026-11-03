# frozen_string_literal: true

# The core's run writes the rows through the ActiveRecord adapter, end to end, against an in-memory
# database: a run keeps the rows, a dry run keeps none, and both report the same failed rows.
RSpec.describe Pipeforge::Engine, "#run writing with the ActiveRecord adapter installed" do
  let(:engine) { described_class.new(source_io: csv_io(csv), target_table: "accounts") }
  let(:company) { AdapterSpecModels::Company.create!(name: "Acme") }
  let(:chunk_results) { [] }
  let(:failed_rows) { chunk_results.flat_map(&:failed_rows) }
  # Row 3 repeats the email of row 1 (the table's unique index refuses it), row 4 has a company that does
  # not exist (the foreign key refuses it), row 5 has no email (the schema refuses it before any write).
  let(:csv) do
    <<~CSV
      Email,Nick,Company
      ann@example.com,ann,#{company.id}
      bob@example.com,bob,#{company.id}
      ann@example.com,again,#{company.id}
      carl@example.com,carl,999999
      ,dee,#{company.id}
      eve@example.com,eve,#{company.id}
    CSV
  end
  let(:mapped_columns) do
    {
      "email" => {source_column: "Email"}, "nickname" => {source_column: "Nick"},
      "company_id" => {source_column: "Company"}
    }
  end

  before { use_settings(execution: {chunk_size: 4}) }

  def run_in(mode:)
    engine.run(mode: mode, mapped_columns: mapped_columns) { |chunk_result| chunk_results << chunk_result }
  end

  def errors_of_row(row_number)
    failed_rows.find { |failed_row| failed_row.row_number == row_number }.errors
  end

  describe "in a run" do
    before { run_in(mode: :run) }

    it "keeps the rows the table took" do
      expect(AdapterSpecModels::Account.pluck(:email)).to contain_exactly("ann@example.com", "bob@example.com", "eve@example.com")
    end

    it "reports the rows the table refused, with the origin database" do
      expect(errors_of_row(3)).to match([a_hash_including(origin: :database, code: :value_not_unique, target_column: nil)])
      expect(errors_of_row(4)).to match([a_hash_including(origin: :database, code: :parent_missing)])
    end

    it "reports a row the schema refused with the origin schema, and does not write it" do
      expect(errors_of_row(5).map { |error| [error[:origin], error[:code]] }).to eq([[:schema, :value_missing]])
    end

    it "goes on after a refused row, so the rows after it are written" do
      expect(AdapterSpecModels::Account.exists?(email: "eve@example.com")).to be(true)
    end

    it "counts the rows written as valid and the others as failed" do
      expect(chunk_results.sum(&:valid_rows_count)).to eq(3)
      expect(chunk_results.sum(&:failed_rows_count)).to eq(3)
    end
  end

  describe "in a dry run" do
    it "keeps no row" do
      run_in(mode: :dry_run)

      expect(AdapterSpecModels::Account.count).to eq(0)
    end

    it "reports the same failed rows as a run" do
      run_in(mode: :dry_run)
      dry_run_failures = failed_rows.map { |failed_row| [failed_row.row_number, failed_row.errors.map { |error| error[:code] }] }

      chunk_results.clear
      run_in(mode: :run)
      run_failures = failed_rows.map { |failed_row| [failed_row.row_number, failed_row.errors.map { |error| error[:code] }] }

      expect(dry_run_failures).to eq(run_failures)
    end

    it "lets a row see the rows written before it in the same run" do
      seen_in_block = []
      engine.run(mode: :dry_run, mapped_columns: mapped_columns) do |_chunk_result|
        seen_in_block << AdapterSpecModels::Account.count
      end

      expect(seen_in_block).to eq([2, 3])
    end
  end
end
