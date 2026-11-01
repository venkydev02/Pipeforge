# frozen_string_literal: true

RSpec.describe Pipeforge::Runtime do
  # Five rows read in chunks of two. Row 3 has no email and row 5 has a status that is too long.
  let(:csv) do
    <<~CSV
      Mail,State,Zip
      a@example.com,ok,10001
      b@example.com,ok,10002
      ,ok,10003
      d@example.com,ok,10004
      e@example.com,far too long,10005
    CSV
  end
  let(:source_reader) { csv_reader(csv) }
  let(:target_columns) do
    [build_target_column(name: "email", required: true), build_target_column(name: "status", max_length: 6)]
  end
  let(:target_schema) { build_target_schema(columns: target_columns) }
  let(:mapped_columns) do
    {
      "email" => {source_column: "Mail"},
      "status" => {source_column: "State", value_mapping: {"ok" => "active"}}
    }
  end
  let(:model_adapter) { FakeModelAdapter.new }
  let(:offset) { 0 }
  let(:limit) { nil }
  let(:mode) { :dry_run }
  let(:chunk_results) { [] }

  before { use_settings(execution: {chunk_size: 2}) }

  def run_all
    described_class.call(
      source_reader: source_reader, mapped_columns: mapped_columns, target_schema: target_schema,
      offset: offset, limit: limit, mode: mode, model_adapter: model_adapter
    ) { |chunk_result| chunk_results << chunk_result }
  end

  describe ".call" do
    subject(:run_result) { run_all }

    it "returns the totals of the run" do
      expect(run_result).to eq(Pipeforge::RunResult.new(processed_rows_count: 5, valid_rows_count: 3, failed_rows_count: 2))
    end

    it "yields the result of each chunk, in order" do
      run_result

      expect(chunk_results.map { |chunk_result| [chunk_result.first_row_number, chunk_result.last_row_number] }).to eq(
        [[1, 2], [3, 4], [5, 5]]
      )
    end

    it "yields the failed rows of each chunk with their absolute row numbers" do
      run_result

      expect(chunk_results.map { |chunk_result| chunk_result.failed_rows.map(&:row_number) }).to eq([[], [3], [5]])
    end

    it "shows the transformed values in a failed row" do
      run_result

      expect(chunk_results.last.failed_rows.first.mapped_values).to eq("email" => "e@example.com", "status" => "far too long")
    end

    it "preloads the parents once for each chunk" do
      run_result

      expect(model_adapter.preload_calls.map(&:size)).to eq([2, 2, 1])
    end

    it "builds one transformer and one schema checker for the whole run" do
      allow(Pipeforge::RowTransformer).to receive(:new).and_call_original
      allow(Pipeforge::SchemaChecker).to receive(:new).and_call_original

      run_result

      expect(Pipeforge::RowTransformer).to have_received(:new).once
      expect(Pipeforge::SchemaChecker).to have_received(:new).once
    end

    it "gives the same totals in a dry run and in a run" do
      dry_run_result = run_all
      run_result_in_run_mode = described_class.call(
        source_reader: source_reader, mapped_columns: mapped_columns, target_schema: target_schema,
        offset: 0, limit: nil, mode: :run, model_adapter: FakeModelAdapter.new
      )

      expect(run_result_in_run_mode).to eq(dry_run_result)
    end

    context "when no block is given" do
      it "still returns the totals" do
        run_result = described_class.call(
          source_reader: source_reader, mapped_columns: mapped_columns, target_schema: target_schema,
          offset: 0, limit: nil, mode: mode, model_adapter: model_adapter
        )

        expect(run_result.processed_rows_count).to eq(5)
      end
    end

    context "with an offset" do
      let(:offset) { 3 }

      it "starts after the rows skipped, with absolute row numbers" do
        run_result

        expect(chunk_results.map { |chunk_result| [chunk_result.first_row_number, chunk_result.last_row_number] }).to eq(
          [[4, 5]]
        )
      end

      it "counts only the rows processed" do
        expect(run_result.processed_rows_count).to eq(2)
      end
    end

    context "with an offset in the middle of a chunk" do
      let(:offset) { 1 }

      it "numbers the rows after it from the next row, and the first chunk is a whole chunk" do
        run_result

        expect(chunk_results.first).to have_attributes(first_row_number: 2, last_row_number: 3)
      end
    end

    context "with a limit" do
      let(:limit) { 3 }

      it "stops after that many rows" do
        expect(run_result.processed_rows_count).to eq(3)
      end

      it "yields the chunks of the rows it processed" do
        run_result

        expect(chunk_results.map(&:processed_rows_count)).to eq([2, 1])
      end
    end

    context "with an offset and a limit" do
      let(:offset) { 1 }
      let(:limit) { 3 }

      it "processes that many rows after the offset" do
        run_result

        expect(chunk_results.map { |chunk_result| [chunk_result.first_row_number, chunk_result.last_row_number] }).to eq(
          [[2, 3], [4, 4]]
        )
      end
    end

    context "with an offset past the end of the file" do
      let(:offset) { 50 }

      it "processes nothing and yields nothing" do
        expect(run_result).to have_attributes(processed_rows_count: 0, valid_rows_count: 0, failed_rows_count: 0)
        expect(chunk_results).to eq([])
      end
    end

    context "with only a header" do
      let(:csv) { "Mail,State\n" }

      it "processes nothing" do
        expect(run_result.processed_rows_count).to eq(0)
      end
    end

    context "when target columns share a source column" do
      let(:target_columns) do
        [build_target_column(name: "email"), build_target_column(name: "login"), build_target_column(name: "status")]
      end
      let(:mapped_columns) do
        {
          "email" => {source_column: "Mail"}, "login" => {source_column: "Mail"}, "status" => {source_column: "State"}
        }
      end

      it "asks the reader for each source column once" do
        allow(source_reader).to receive(:each_chunk).and_call_original

        run_result

        expect(source_reader).to have_received(:each_chunk).with(offset: 0, limit: nil, columns: %w[Mail State])
      end
    end

    context "when a row is too long for the header" do
      let(:csv) { "Mail,State\na@example.com,ok,extra\n" }

      it "stops with the reader's error" do
        expect { run_result }.to raise_error(Pipeforge::Source::MalformedSourceError) do |error|
          expect(error.codes).to eq([:source_row_too_long])
        end
      end
    end
  end
end
