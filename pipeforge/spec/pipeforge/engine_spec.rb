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
        "status" => {source_column: "Status"},
        "code" => {source_column: "Code"},
        "note" => {source_column: "Note"}
      }
    end

    before { allow(Pipeforge::TargetAdapter).to receive(:schema).and_return(schema) }

    it "names the source file" do
      expect(result.source_identifier).to eq(source_io.path)
    end

    it "returns a summary for each mapped column, keyed by target column" do
      expect(result.columns.keys).to eq(%w[status code note])
    end

    it "gives each summary its source column" do
      expect(result.columns["code"].source_column).to eq("Code")
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
        expect(result.columns["code"].distinct_values[:compatible].values.size).to eq(2)
      end
    end

    context "when only some columns are mapped" do
      let(:mapped_columns) { {"code" => {source_column: "Code"}} }

      it "measures only those columns" do
        expect(result.columns.keys).to eq(["code"])
      end
    end

    context "when a mapped column is not in the file" do
      let(:mapped_columns) { {"status" => {source_column: "Nope"}} }

      it "stops with mapped_column_not_in_file, naming the column" do
        expect { result }.to raise_error(Pipeforge::InvalidMappedColumnsError) do |error|
          expect(error.errors.map { |entry| entry.slice(:code, :target_column, :source_column) }).to eq(
            [{code: :mapped_column_not_in_file, target_column: "status", source_column: "Nope"}]
          )
        end
      end
    end

    context "with the same source column for two target columns" do
      let(:mapped_columns) { {"status" => {source_column: "Status"}, "code" => {source_column: "Status"}} }

      it "measures it once for each target column" do
        expect(result.columns.keys).to eq(%w[status code])
        expect(result.columns.values.map(&:source_column)).to eq(%w[Status Status])
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
      let(:mapped_columns) { {"status" => {source_column: "Status"}} }

      it "measures the values against that type and size" do
        expect(result.columns["status"].type_compatibility).to eq(fits: 5, total: 7)
      end
    end

    context "with an enum column in the schema" do
      let(:source_io) { csv_io("Status\ndraft\n1\nshipped\n7\nPlaced\n") }
      let(:target_columns) do
        [build_target_column(name: "status", type: "integer", enum_values: {"draft" => 0, "placed" => 1, "shipped" => 2})]
      end
      let(:mapped_columns) { {"status" => {source_column: "Status"}} }

      it "counts the labels and the stored values as fitting, and nothing else" do
        expect(result.columns["status"].type_compatibility).to eq(fits: 3, total: 5)
      end
    end

    context "when the caller sends a type with a column" do
      let(:target_columns) { [build_target_column(name: "code", type: "integer")] }
      let(:mapped_columns) { {"code" => {source_column: "Code", type: "string"}} }

      it "uses the type of the schema instead" do
        expect(result.columns["code"].type_compatibility).to eq(fits: 0, total: 7)
      end
    end

    context "when a mapped column is unusable" do
      context "without a source column" do
        let(:mapped_columns) { {"status" => {}} }

        it "raises InvalidMappedColumnsError, naming the target column" do
          expect { result }.to raise_error(Pipeforge::InvalidMappedColumnsError, "status has no source_column")
        end

        it "gives the code column_missing_source_column, with the column" do
          expect { result }.to raise_error(Pipeforge::InvalidMappedColumnsError) do |error|
            expect(error.errors).to eq(
              [{code: :column_missing_source_column, message: "status has no source_column", target_column: "status"}]
            )
          end
        end
      end

      context "with a target column that is not in the schema" do
        let(:mapped_columns) { {"state" => {source_column: "Status"}} }

        it "gives the code target_column_not_in_schema, with the columns and the table" do
          expect { result }.to raise_error(Pipeforge::InvalidMappedColumnsError) do |error|
            expect(error.errors.map { |entry| entry.except(:message) }).to eq(
              [{code: :target_column_not_in_schema, source_column: "Status", target_column: "state", table: "records"}]
            )
          end
        end

        it "names the source column, the target column and the table in the message" do
          expect { result }.to raise_error(Pipeforge::InvalidMappedColumnsError, /state.*records/)
        end
      end

      context "with a required target column that has no entry" do
        let(:target_columns) { [build_target_column(name: "status", required: true), build_target_column(name: "code")] }
        let(:mapped_columns) { {"code" => {source_column: "Code"}} }

        it "gives the code required_column_unmapped, with the target column" do
          expect { result }.to raise_error(Pipeforge::InvalidMappedColumnsError) do |error|
            expect(error.errors.map { |entry| entry.slice(:code, :target_column) }).to eq(
              [{code: :required_column_unmapped, target_column: "status"}]
            )
          end
        end
      end

      context "in several columns" do
        let(:mapped_columns) do
          {"status" => {}, "nowhere" => {source_column: "Code"}, "note" => {source_column: "Note"}}
        end

        it "lists every error in one error, in order" do
          expect { result }.to raise_error(Pipeforge::InvalidMappedColumnsError) do |error|
            expect(error.errors.map { |entry| entry.slice(:code, :target_column) }).to eq(
              [
                {code: :column_missing_source_column, target_column: "status"},
                {code: :target_column_not_in_schema, target_column: "nowhere"}
              ]
            )
          end
        end
      end

      context "together with a column that is not in the file" do
        let(:mapped_columns) { {"status" => {}, "code" => {source_column: "Gone"}} }

        it "reports both in one error" do
          expect { result }.to raise_error(Pipeforge::InvalidMappedColumnsError) do |error|
            expect(error.errors.map { |entry| entry.slice(:code, :target_column) }).to eq(
              [
                {code: :column_missing_source_column, target_column: "status"},
                {code: :mapped_column_not_in_file, target_column: "code"}
              ]
            )
          end
        end
      end

      context "when the columns are checked" do
        let(:mapped_columns) { {"status" => {}} }

        it "does not create a value analyzer" do
          allow(Pipeforge::ValueAnalyzer).to receive(:call).and_call_original

          expect { result }.to raise_error(Pipeforge::InvalidMappedColumnsError)
          expect(Pipeforge::ValueAnalyzer).not_to have_received(:call)
        end
      end
    end

    context "with a value mapping whose keys are not text" do
      let(:source_io) { csv_io("Count\n1\n2\n") }
      let(:target_columns) { [build_target_column(name: "count", type: "integer")] }
      let(:mapped_columns) do
        {"count" => {source_column: "Count", value_mapping: {1 => "x", 2 => "20"}}}
      end

      it "applies the mapping, because the keys are turned into text" do
        # 1 maps to x, which does not fit an integer; 2 maps to 20, which fits.
        expect(result.columns["count"].type_compatibility).to eq(fits: 1, total: 2)
      end

      it "returns the mapping with its keys as text" do
        expect(result.columns["count"].value_mapping).to eq("1" => "x", "2" => "20")
      end

      context "when two keys give the same text" do
        let(:mapped_columns) do
          {"count" => {source_column: "Count", value_mapping: {1 => "x", "1" => "20"}}}
        end

        it "makes them one key, and the later one is used" do
          expect(result.columns["count"].value_mapping).to eq("1" => "20")
        end
      end
    end

    context "with a column that has no value mapping" do
      let(:source_io) { csv_io("Count\n1\n") }
      let(:target_columns) { [build_target_column(name: "count", type: "integer")] }
      let(:mapped_columns) { {"count" => {source_column: "Count"}} }

      it "returns an empty value mapping for it" do
        expect(result.columns["count"].value_mapping).to eq({})
      end
    end

    context "with a value mapping on a column" do
      let(:target_columns) { [build_target_column(name: "status", type: "integer")] }
      let(:mapped_columns) { {"status" => {source_column: "Status", value_mapping: value_mapping}} }
      let(:value_mapping) { {"Active" => "1", "A" => "x"} }

      it "measures the values as the values they map to" do
        expect(result.columns["status"].type_compatibility).to eq(fits: 4, total: 7)
      end

      it "returns the value mapping with the column" do
        expect(result.columns["status"].value_mapping).to eq(value_mapping)
      end

      context "when it is called again with an edited value mapping" do
        let(:edited_mapped_columns) do
          {
            "status" => {
              source_column: "Status",
              value_mapping: {"Active" => "1", "INACTIVE" => "0", "A" => "2"}
            }
          }
        end

        it "shows the facts again, now that every value fits" do
          edited_result = engine.analyze_values(mapped_columns: edited_mapped_columns)

          expect(edited_result.columns["status"].type_compatibility).to eq(fits: 7, total: 7)
        end
      end
    end
  end

  describe "the schema of the target table" do
    let(:source_io) { csv_io("Status,Code\n1,2\n") }
    let(:target_columns) { [build_target_column(name: "status"), build_target_column(name: "code")] }

    before { allow(Pipeforge::TargetAdapter).to receive(:schema).and_return(schema) }

    it "is read from the adapter once, however many times the stages are called" do
      engine.analyze_headers
      engine.analyze_values(mapped_columns: {"status" => {source_column: "Status"}})
      engine.analyze_values(mapped_columns: {"code" => {source_column: "Code"}})

      expect(Pipeforge::TargetAdapter).to have_received(:schema).once
    end

    context "when reading it fails" do
      let(:schema_error) do
        Pipeforge::TargetSchemaError.single(code: :target_table_not_found, message: "no such table", table: "records")
      end

      it "asks the adapter again on the next call" do
        allow(Pipeforge::TargetAdapter).to receive(:schema).and_raise(schema_error)
        expect { engine.analyze_headers }.to raise_error(Pipeforge::TargetSchemaError)

        allow(Pipeforge::TargetAdapter).to receive(:schema).and_return(schema)

        expect(engine.analyze_headers.matches.keys).to eq(%w[status code])
      end
    end
  end
end
