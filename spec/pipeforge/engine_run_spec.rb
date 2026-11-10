# frozen_string_literal: true

RSpec.describe Pipeforge::Engine, "#run" do
  subject(:engine) { described_class.new(source_io: csv_io(csv), target_model: "Record") }

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

  def run_engine(run_mode: mode, **options)
    engine.run(mode: run_mode, mapped_columns: mapped_columns, **options) { |chunk_result| chunk_results << chunk_result }
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

    expect(Pipeforge::TargetAdapter).to have_received(:model_adapter).with(target_model: "Record")
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

  context "with an offset" do
    it "processes the rows after it to the end of the file, with absolute row numbers" do
      run_engine(offset: 1)

      expect(chunk_results.flat_map(&:failed_rows).map(&:row_number)).to eq([2])
      expect(chunk_results.map(&:processed_rows_count)).to eq([2])
    end
  end

  context "with a chunk size" do
    it "yields chunks of that size" do
      run_engine(chunk_size: 1)

      expect(chunk_results.map(&:processed_rows_count)).to eq([1, 1, 1])
    end

    it "overrides the chunk size of the settings for that call" do
      run_engine(chunk_size: 3)

      expect(chunk_results.map(&:processed_rows_count)).to eq([3])
    end

    it "gives the same totals as the chunk size of the settings" do
      expect(run_engine(chunk_size: 1)).to eq(run_engine)
    end

    it "uses the chunk size of the settings when none is given" do
      run_engine

      expect(chunk_results.map(&:processed_rows_count)).to eq([2, 1])
    end
  end

  shared_examples "an argument the engine refuses" do |arguments, message|
    it "stops with an ArgumentError that names the argument and the value" do
      expect { run_engine(**arguments) }.to raise_error(ArgumentError, message)
    end

    it "stops before a row is read or a transaction is opened" do
      expect { run_engine(**arguments) }.to raise_error(ArgumentError)

      expect(model_adapter.built_attributes).to eq([])
      expect(model_adapter.transaction_calls).to eq([])
    end
  end

  context "with a mode that is not :dry_run or :run" do
    context "when it is a misspelled symbol" do
      include_examples "an argument the engine refuses", {run_mode: :dryrun},
        "mode must be :dry_run or :run, got :dryrun"
    end

    context "when it is text" do
      include_examples "an argument the engine refuses", {run_mode: "dry_run"},
        'mode must be :dry_run or :run, got "dry_run"'
    end

    context "when it is the text run" do
      include_examples "an argument the engine refuses", {run_mode: "run"},
        'mode must be :dry_run or :run, got "run"'
    end

    context "when it is nil" do
      include_examples "an argument the engine refuses", {run_mode: nil}, "mode must be :dry_run or :run, got nil"
    end
  end

  context "with the mode :run" do
    it "is accepted, and writes the rows" do
      expect(run_engine(run_mode: :run)).to have_attributes(processed_rows_count: 3, valid_rows_count: 2)
    end
  end

  context "with an offset that is not a whole number of at least 0" do
    context "when it is negative" do
      include_examples "an argument the engine refuses", {offset: -1},
        "offset must be a whole number of at least 0, got -1"
    end

    context "when it is a decimal number" do
      include_examples "an argument the engine refuses", {offset: 1.5},
        "offset must be a whole number of at least 0, got 1.5"
    end

    context "when it is text" do
      include_examples "an argument the engine refuses", {offset: "2"},
        'offset must be a whole number of at least 0, got "2"'
    end

    context "when it is nil" do
      include_examples "an argument the engine refuses", {offset: nil},
        "offset must be a whole number of at least 0, got nil"
    end

    context "when it is true" do
      include_examples "an argument the engine refuses", {offset: true},
        "offset must be a whole number of at least 0, got true"
    end
  end

  context "with an offset of 0" do
    it "is accepted, and processes every row" do
      expect(run_engine(offset: 0)).to have_attributes(processed_rows_count: 3)
    end
  end

  context "with an offset past the end of the file" do
    it "is accepted, and processes nothing" do
      expect(run_engine(offset: 100)).to have_attributes(processed_rows_count: 0)
    end
  end

  context "with a chunk size that is not a whole number of at least 1" do
    context "when it is 0" do
      include_examples "an argument the engine refuses", {chunk_size: 0},
        "chunk_size must be a whole number of at least 1, got 0"
    end

    context "when it is negative" do
      include_examples "an argument the engine refuses", {chunk_size: -5},
        "chunk_size must be a whole number of at least 1, got -5"
    end

    context "when it is a decimal number" do
      include_examples "an argument the engine refuses", {chunk_size: 2.5},
        "chunk_size must be a whole number of at least 1, got 2.5"
    end

    context "when it is text" do
      include_examples "an argument the engine refuses", {chunk_size: "big"},
        'chunk_size must be a whole number of at least 1, got "big"'
    end

    context "when it is nil" do
      include_examples "an argument the engine refuses", {chunk_size: nil},
        "chunk_size must be a whole number of at least 1, got nil"
    end
  end

  context "with several arguments that cannot be used" do
    it "lists every one in a single ArgumentError, in the order mode, offset, chunk_size" do
      expect { run_engine(run_mode: :dryrun, offset: -1, chunk_size: 0) }.to raise_error(
        ArgumentError,
        "mode must be :dry_run or :run, got :dryrun; " \
        "offset must be a whole number of at least 0, got -1; " \
        "chunk_size must be a whole number of at least 1, got 0"
      )
    end

    it "lists only the ones that cannot be used" do
      expect { run_engine(offset: -1) }.to raise_error(
        ArgumentError, "offset must be a whole number of at least 0, got -1"
      )
    end
  end

  context "when an argument and the mapped columns are both wrong" do
    let(:mapped_columns) { {"level" => {source_column: "Level"}} }

    it "reports the argument first, because it is checked before the mapped columns" do
      expect { run_engine(chunk_size: 0) }.to raise_error(ArgumentError)
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
