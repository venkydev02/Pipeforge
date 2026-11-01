# frozen_string_literal: true

RSpec.describe Pipeforge::Engine, "#run" do
  subject(:engine) { described_class.new(source_io: csv_io(csv), target_table: "records") }

  let(:csv) { "Mail,Level\na@example.com,1\n,2\nc@example.com,3\n" }
  let(:target_columns) do
    [build_target_column(name: "email", required: true), build_target_column(name: "level", max_length: 3)]
  end
  let(:schema) { build_target_schema(table_name: "records", model: "Record", columns: target_columns) }
  let(:model_adapter) { FakeModelAdapter.new }
  let(:mapped_columns) { {"email" => {source_column: "Mail"}, "level" => {source_column: "Level"}} }
  let(:mode) { :dry_run }
  let(:chunk_results) { [] }

  # The core is tested without an adapter gem, so the adapter calls are stubbed.
  before do
    allow(Pipeforge::TargetAdapter).to receive(:ensure_installed)
    allow(Pipeforge::TargetAdapter).to receive(:schema).and_return(schema)
    allow(Pipeforge::TargetAdapter).to receive(:model_adapter).and_return(model_adapter)
    use_settings(execution: {chunk_size: 2})
  end

  def run_engine(**options)
    engine.run(mode: mode, mapped_columns: mapped_columns, **options) { |chunk_result| chunk_results << chunk_result }
  end

  it "returns the totals of the run" do
    expect(run_engine).to have_attributes(processed_rows_count: 3, valid_rows_count: 2, failed_rows_count: 1)
  end

  it "yields the result of each chunk" do
    run_engine

    expect(chunk_results.map(&:processed_rows_count)).to eq([2, 1])
  end

  it "reports the failed rows with their row number and code" do
    run_engine

    failed_rows = chunk_results.flat_map(&:failed_rows)

    expect(failed_rows.map { |failed_row| [failed_row.row_number, failed_row.errors.first[:code]] }).to eq([[2, :value_missing]])
  end

  it "asks the adapter for the model adapter of the table it was given" do
    run_engine

    expect(Pipeforge::TargetAdapter).to have_received(:model_adapter).with(target_table: "records")
  end

  it "gives the same result in a dry run and in a run" do
    dry_run_result = engine.run(mode: :dry_run, mapped_columns: mapped_columns)

    expect(engine.run(mode: :run, mapped_columns: mapped_columns)).to eq(dry_run_result)
  end

  it "can be called again on the same engine" do
    first_result = run_engine

    expect(run_engine).to eq(first_result)
  end

  it "works without a block" do
    expect(engine.run(mode: mode, mapped_columns: mapped_columns).processed_rows_count).to eq(3)
  end

  context "with an offset and a limit" do
    it "processes only those rows, with absolute row numbers" do
      run_engine(offset: 1, limit: 1)

      expect(chunk_results.flat_map(&:failed_rows).map(&:row_number)).to eq([2])
    end
  end

  context "with a value mapping whose keys are numbers" do
    let(:mapped_columns) do
      {"email" => {source_column: "Mail"}, "level" => {source_column: "Level", value_mapping: {1 => "one", 3 => "tre"}}}
    end

    it "applies it to the values of the file, which are text" do
      run_engine

      expect(model_adapter.built_attributes.map { |attributes| attributes["level"] }).to eq(%w[one 2 tre])
    end

    it "shows the mapped values in a failed row" do
      run_engine

      expect(chunk_results.flat_map(&:failed_rows).first.mapped_values).to eq("email" => nil, "level" => "2")
    end
  end

  context "when a required column is not mapped" do
    let(:mapped_columns) { {"level" => {source_column: "Level"}} }

    it "stops with required_column_unmapped, before any row is read" do
      expect { run_engine }.to raise_error(Pipeforge::InvalidMappedColumnsError) do |error|
        expect(error.codes).to eq([:required_column_unmapped])
      end

      expect(model_adapter.built_attributes).to eq([])
    end
  end

  context "when several mapped columns are wrong" do
    let(:mapped_columns) { {"nope" => {source_column: "Mail"}, "level" => {source_column: "Missing"}} }

    it "lists every mistake together" do
      expect { run_engine }.to raise_error(Pipeforge::InvalidMappedColumnsError) do |error|
        expect(error.codes).to contain_exactly(:target_column_not_in_schema, :mapped_column_not_in_file, :required_column_unmapped)
      end
    end
  end
end
