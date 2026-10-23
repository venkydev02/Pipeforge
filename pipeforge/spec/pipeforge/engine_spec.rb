# frozen_string_literal: true

RSpec.describe Pipeforge::Engine do
  subject(:engine) { described_class.new(source_io: source_io, target_table: "records") }

  # The settings the parts of the engine read from Configuration.
  let(:settings) { {} }
  # Status: Active x4 (one written " Active "), INACTIVE x2, A x1. Code: seven different values.
  let(:source_io) { File.open(File.expand_path("../fixtures/source/statuses.csv", __dir__)) }
  # The columns of the target table; each spec context changes only the ones it cares about.
  let(:target_columns) do
    [
      build_target_column(name: "status"),
      build_target_column(name: "code"),
      build_target_column(name: "note")
    ]
  end
  let(:schema) { build_target_schema(table_name: "records", model: "Record", columns: target_columns) }

  # The core is tested without an adapter gem, so the check that one is installed is stubbed.
  before { allow(Pipeforge::TargetAdapter).to receive(:ensure_installed) }

  before { use_settings(settings) }

  describe ".new" do
    context "when no target adapter is installed" do
      before { allow(Pipeforge::TargetAdapter).to receive(:ensure_installed).and_call_original }

      it "stops with target_adapter_not_installed" do
        expect { engine }.to raise_error(Pipeforge::TargetAdapterError) do |error|
          expect(error.codes).to eq([:target_adapter_not_installed])
        end
      end
    end

    context "when the source is missing a method" do
      let(:source_io) { Object.new }

      it "stops with our own error, naming the missing methods" do
        expect { engine }.to raise_error(Pipeforge::Source::UnsupportedSourceError, /read.*rewind.*seek/)
      end
    end
  end

  describe "#analyze_headers" do
    subject(:result) { engine.analyze_headers }

    let(:source_io) { csv_io("Status,Code,Note\n1,2,3\n") }
    let(:target_columns) { [build_target_column(name: "status"), build_target_column(name: "code")] }

    context "with an adapter installed" do
      before { allow(Pipeforge::TargetAdapter).to receive(:schema).and_return(schema) }

      it "matches the source columns to the target columns" do
        expect(result.matches.transform_values { |match| match[:source_column] }).to eq(
          "status" => "Status", "code" => "Code"
        )
      end

      it "lists the source columns without a match" do
        expect(result.unmatched_source_columns).to eq(%w[Note])
      end

      it "asks the adapter for the table it was given" do
        result

        expect(Pipeforge::TargetAdapter).to have_received(:schema).with(target_table: "records")
      end

      it "names the source by its class when it has no path" do
        expect(result.source_identifier).to eq("StringIO")
      end

      context "with a higher inclusion threshold in the settings" do
        let(:settings) { {recommendation: {inclusion_threshold: 100}} }
        let(:source_io) { csv_io("Stat,Code\n1,2\n") }

        it "leaves a weaker pair unmatched instead of a match" do
          expect(result.matches.keys).to eq(%w[code])
          expect(result.unmatched_source_columns).to eq(%w[Stat])
        end
      end

      context "when the file is empty" do
        let(:source_io) { csv_io("") }

        it "stops with source_empty, before the target schema is read" do
          expect { result }.to raise_error(Pipeforge::Source::EmptySourceError)
          expect(Pipeforge::TargetAdapter).not_to have_received(:schema)
        end
      end

      context "when a header cell is blank" do
        let(:source_io) { csv_io("Status,,Code\n1,2,3\n") }

        it "stops with source_header_blank, before the target schema is read" do
          expect { result }.to raise_error(Pipeforge::Source::InvalidHeaderError) do |error|
            expect(error.codes).to eq([:source_header_blank])
          end
          expect(Pipeforge::TargetAdapter).not_to have_received(:schema)
        end
      end

      context "when a name appears twice" do
        let(:source_io) { csv_io("Status,Status,Code\n1,2,3\n") }

        it "stops with source_header_duplicated, before the target schema is read" do
          expect { result }.to raise_error(Pipeforge::Source::InvalidHeaderError) do |error|
            expect(error.codes).to eq([:source_header_duplicated])
          end
          expect(Pipeforge::TargetAdapter).not_to have_received(:schema)
        end
      end
    end
  end

  describe "#analyze_values" do
    subject(:result) { engine.analyze_values(mapped_columns: mapped_columns) }

    let(:mapped_columns) do
      {
        "Status" => {target_column: "status"},
        "Code" => {target_column: "code"},
        "Note" => {target_column: "note"}
      }
    end

    before { allow(Pipeforge::TargetAdapter).to receive(:schema).and_return(schema) }

    it "names the source file" do
      expect(result.source_identifier).to eq(source_io.path)
    end

    it "returns a summary for each mapped column, keyed by source column" do
      expect(result.columns.keys).to eq(%w[Status Code Note])
    end

    it "gives each summary its target column" do
      expect(result.columns["Code"].target_column).to eq("code")
    end

    it "returns the same result when it is called again" do
      expect(engine.analyze_values(mapped_columns: mapped_columns).to_h).to eq(result.to_h)
    end

    it "asks the adapter for the table it was given" do
      result

      expect(Pipeforge::TargetAdapter).to have_received(:schema).with(target_table: "records")
    end

    context "with a cap on the distinct values in the settings" do
      let(:settings) { {source: {distinct_values_cap: 2}} }

      it "lists at most that many values per list" do
        expect(result.columns["Code"].distinct_values[:compatible].values.size).to eq(2)
      end
    end

    context "when only some columns are mapped" do
      let(:mapped_columns) { {"Code" => {target_column: "code"}} }

      it "measures only those columns" do
        expect(result.columns.keys).to eq(["Code"])
      end
    end

    context "when a mapped column is not in the file" do
      let(:mapped_columns) { {"Nope" => {target_column: "status"}} }

      it "stops with mapped_column_not_in_file, naming the column" do
        expect { result }.to raise_error(Pipeforge::InvalidMappedColumnsError) do |error|
          expect(error.errors.map { |entry| entry.slice(:code, :source_column) }).to eq(
            [{code: :mapped_column_not_in_file, source_column: "Nope"}]
          )
        end
      end
    end

    context "when the header of the file cannot be used" do
      let(:source_io) { csv_io("Status,,Code\n1,2,3\n") }

      it "stops with the header error before the mapped columns are checked" do
        expect { result }.to raise_error(Pipeforge::Source::InvalidHeaderError)
      end
    end

    context "with the type of the target column in the schema" do
      let(:target_columns) { [build_target_column(name: "status", type: "string", max_length: 6)] }
      let(:mapped_columns) { {"Status" => {target_column: "status"}} }

      it "measures the values against that type and size" do
        expect(result.columns["Status"].type_compatibility).to eq(fits: 5, total: 7)
      end
    end

    context "when the caller sends a type with a column" do
      let(:target_columns) { [build_target_column(name: "code", type: "integer")] }
      let(:mapped_columns) { {"Code" => {target_column: "code", type: "string"}} }

      it "uses the type of the schema instead" do
        expect(result.columns["Code"].type_compatibility).to eq(fits: 0, total: 7)
      end
    end

    context "when a mapped column is unusable" do
      context "without a target column" do
        let(:mapped_columns) { {"Status" => {}} }

        it "raises InvalidMappedColumnsError, naming the source column" do
          expect { result }.to raise_error(Pipeforge::InvalidMappedColumnsError, "Status has no target_column")
        end

        it "gives the code column_missing_target_column, with the column" do
          expect { result }.to raise_error(Pipeforge::InvalidMappedColumnsError) do |error|
            expect(error.errors).to eq(
              [{code: :column_missing_target_column, message: "Status has no target_column", source_column: "Status"}]
            )
          end
        end
      end

      context "with a target column that is not in the schema" do
        let(:mapped_columns) { {"Status" => {target_column: "state"}} }

        it "gives the code target_column_not_in_schema, with the columns and the table" do
          expect { result }.to raise_error(Pipeforge::InvalidMappedColumnsError) do |error|
            expect(error.errors.map { |entry| entry.except(:message) }).to eq(
              [{code: :target_column_not_in_schema, source_column: "Status", target_column: "state", table: "records"}]
            )
          end
        end

        it "names the source column, the target column and the table in the message" do
          expect { result }.to raise_error(Pipeforge::InvalidMappedColumnsError, /Status.*state.*records/)
        end
      end

      context "in several columns" do
        let(:mapped_columns) do
          {"Status" => {}, "Code" => {target_column: "nowhere"}, "Note" => {target_column: "note"}}
        end

        it "lists every error in one error, in order" do
          expect { result }.to raise_error(Pipeforge::InvalidMappedColumnsError) do |error|
            expect(error.errors.map { |entry| entry.slice(:code, :source_column) }).to eq(
              [
                {code: :column_missing_target_column, source_column: "Status"},
                {code: :target_column_not_in_schema, source_column: "Code"}
              ]
            )
          end
        end
      end

      context "together with a column that is not in the file" do
        let(:mapped_columns) { {"Status" => {}, "Gone" => {target_column: "code"}} }

        it "reports both in one error" do
          expect { result }.to raise_error(Pipeforge::InvalidMappedColumnsError) do |error|
            expect(error.errors.map { |entry| entry.slice(:code, :source_column) }).to eq(
              [
                {code: :column_missing_target_column, source_column: "Status"},
                {code: :mapped_column_not_in_file, source_column: "Gone"}
              ]
            )
          end
        end
      end

      context "when the columns are checked" do
        let(:mapped_columns) { {"Status" => {}} }

        it "does not create a value analyzer" do
          allow(Pipeforge::ValueAnalyzer).to receive(:call).and_call_original

          expect { result }.to raise_error(Pipeforge::InvalidMappedColumnsError)
          expect(Pipeforge::ValueAnalyzer).not_to have_received(:call)
        end
      end
    end

    context "with a value mapping on a column" do
      let(:target_columns) { [build_target_column(name: "status", type: "integer")] }
      let(:mapped_columns) { {"Status" => {target_column: "status", value_mapping: value_mapping}} }
      let(:value_mapping) { {"Active" => "1", "A" => "x"} }

      it "measures the values as the values they map to" do
        expect(result.columns["Status"].type_compatibility).to eq(fits: 4, total: 7)
      end

      it "returns the value mapping with the column" do
        expect(result.columns["Status"].value_mapping).to eq(value_mapping)
      end

      context "when it is called again with an edited value mapping" do
        let(:edited_mapped_columns) do
          {
            "Status" => {
              target_column: "status",
              value_mapping: {"Active" => "1", "INACTIVE" => "0", "A" => "2"}
            }
          }
        end

        it "shows the facts again, now that every value fits" do
          edited_result = engine.analyze_values(mapped_columns: edited_mapped_columns)

          expect(edited_result.columns["Status"].type_compatibility).to eq(fits: 7, total: 7)
        end
      end
    end
  end
end
