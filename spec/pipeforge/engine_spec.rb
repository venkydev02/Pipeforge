# frozen_string_literal: true

RSpec.describe Pipeforge::Engine do
  subject(:engine) { described_class.new(source_io: source_io, target_model_name: "Record") }

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
  let(:schema) { build_target_schema(table_name: "records", model_name: "Record", columns: target_columns) }

  # The core is tested without an adapter gem, so the engine builds a fake target from a stand-in for the target
  # class an adapter gem installs. The target gives the schema, and it casts the texts of the column values stage:
  # it reads a text as the type of its column and cannot read any other text.
  let(:types) do
    target_columns.to_h do |target_column|
      [target_column.name, target_column.enum_labels.nil? ? target_column.type : "string"]
    end
  end
  let(:target) { FakeTarget.reading(types: types, schema: schema) }
  let(:target_class) { double("target class", new: target) }

  before { allow(Pipeforge::Engine).to receive(:target_class).and_return(target_class) }

  before { use_settings(settings) }

  describe ".new" do
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

    it "matches the source columns to the target columns" do
      expect(result.matches.map { |match| [match[:target_column_name], match[:source_column_name]] }).to eq(
        [["status", "Status"], ["code", "Code"]]
      )
    end

    it "lists the source columns without a match" do
      expect(result.unmatched_source_column_names).to eq(%w[Note])
    end

    it "builds the target of the model it was given" do
      result

      expect(target_class).to have_received(:new).with(target_model_name: "Record")
    end

    it "names the source by its class when it has no path" do
      expect(result.source_identifier).to eq("StringIO")
    end

    context "with a higher inclusion threshold in the settings" do
      let(:settings) { {recommendation: {inclusion_threshold: 100}} }
      let(:source_io) { csv_io("Stat,Code\n1,2\n") }

      it "leaves a weaker pair unmatched instead of a match" do
        expect(result.matches.map { |match| match[:target_column_name] }).to eq(%w[code])
        expect(result.unmatched_source_column_names).to eq(%w[Stat])
      end
    end

    context "when the file is empty" do
      let(:source_io) { csv_io("") }

      it "stops with source_empty, before the target is built" do
        expect { result }.to raise_error(Pipeforge::Source::EmptySourceError)
        expect(target_class).not_to have_received(:new)
      end
    end

    context "when a header cell is blank" do
      let(:source_io) { csv_io("Status,,Code\n1,2,3\n") }

      it "stops with source_header_blank, before the target is built" do
        expect { result }.to raise_error(Pipeforge::Source::InvalidHeaderError) do |error|
          expect(error.codes).to eq([:source_header_blank])
        end
        expect(target_class).not_to have_received(:new)
      end
    end

    context "when a name appears twice" do
      let(:source_io) { csv_io("Status,Status,Code\n1,2,3\n") }

      it "stops with source_header_duplicated, before the target is built" do
        expect { result }.to raise_error(Pipeforge::Source::InvalidHeaderError) do |error|
          expect(error.codes).to eq([:source_header_duplicated])
        end
        expect(target_class).not_to have_received(:new)
      end
    end
  end

  describe "#analyze_column_values" do
    subject(:result) { engine.analyze_column_values(mapped_columns: mapped_columns) }

    let(:mapped_columns) do
      {
        "status" => {source_column_name: "Status"},
        "code" => {source_column_name: "Code"},
        "note" => {source_column_name: "Note"}
      }
    end

    it "names the source file" do
      expect(result.source_identifier).to eq(source_io.path)
    end

    it "builds the target of the model it was given" do
      result

      expect(target_class).to have_received(:new).with(target_model_name: "Record")
    end

    it "checks each value as the value the target casts it to" do
      short_string = build_target_column(name: "status", type: "string", max_length: 1)
      cast_to_one_letter = FakeTarget.new(
        casts: ->(column_name:, value:) { "x" }, schema: build_target_schema(columns: [short_string])
      )
      allow(target_class).to receive(:new).and_return(cast_to_one_letter)

      checked = engine.analyze_column_values(mapped_columns: {"status" => {source_column_name: "Status"}})

      expect(checked.column_summaries["status"].distinct_values).to have_attributes(compatible_count: 7, incompatible_count: 0)
    end

    it "returns a summary for each mapped column, keyed by target column" do
      expect(result.column_summaries.keys).to eq(%w[status code note])
    end

    it "gives each summary its source column" do
      expect(result.column_summaries["code"].source_column_name).to eq("Code")
    end

    it "returns the same result when it is called again" do
      expect(engine.analyze_column_values(mapped_columns: mapped_columns).to_h).to eq(result.to_h)
    end

    context "when only some columns are mapped" do
      let(:mapped_columns) { {"code" => {source_column_name: "Code"}} }

      it "measures only those columns" do
        expect(result.column_summaries.keys).to eq(["code"])
      end
    end

    context "when a mapped column is not in the file" do
      let(:mapped_columns) { {"status" => {source_column_name: "Nope"}} }

      it "stops with mapped_column_not_in_file, naming the column" do
        expect { result }.to raise_error(Pipeforge::InvalidMappedColumnsError) do |error|
          expect(error.errors.map { |entry| entry.slice(:code, :target_column_name, :source_column_name) }).to eq(
            [{code: :mapped_column_not_in_file, target_column_name: "status", source_column_name: "Nope"}]
          )
        end
      end
    end

    context "with the same source column for two target columns" do
      let(:mapped_columns) { {"status" => {source_column_name: "Status"}, "code" => {source_column_name: "Status"}} }

      it "measures it once for each target column" do
        expect(result.column_summaries.keys).to eq(%w[status code])
        expect(result.column_summaries.values.map(&:source_column_name)).to eq(%w[Status Status])
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
      let(:mapped_columns) { {"status" => {source_column_name: "Status"}} }

      it "measures the values against that type and size" do
        expect(result.column_summaries["status"].distinct_values).to have_attributes(compatible_count: 5, incompatible_count: 2)
      end
    end

    context "with an enum column in the schema" do
      let(:source_io) { csv_io("Status\ndraft\n1\nshipped\n7\nPlaced\n") }
      let(:target_columns) do
        [build_target_column(name: "status", type: "integer", enum_labels: %w[draft placed shipped])]
      end
      let(:mapped_columns) { {"status" => {source_column_name: "Status"}} }

      it "counts the labels as fitting, and nothing else" do
        expect(result.column_summaries["status"].distinct_values).to have_attributes(compatible_count: 2, incompatible_count: 3)
      end
    end

    context "when the caller sends a type with a column" do
      let(:target_columns) { [build_target_column(name: "code", type: "integer")] }
      let(:mapped_columns) { {"code" => {source_column_name: "Code", type: "string"}} }

      it "uses the type of the schema instead" do
        expect(result.column_summaries["code"].distinct_values).to have_attributes(compatible_count: 0, incompatible_count: 7)
      end
    end

    context "when a mapped column is unusable" do
      context "without a source column" do
        let(:mapped_columns) { {"status" => {}} }

        it "raises InvalidMappedColumnsError, naming the target column" do
          expect { result }.to raise_error(Pipeforge::InvalidMappedColumnsError, "status has no source_column_name")
        end

        it "gives the code column_missing_source_column, with the column" do
          expect { result }.to raise_error(Pipeforge::InvalidMappedColumnsError) do |error|
            expect(error.errors).to eq(
              [{code: :column_missing_source_column, message: "status has no source_column_name", target_column_name: "status"}]
            )
          end
        end
      end

      context "with a target column that is not in the schema" do
        let(:mapped_columns) { {"state" => {source_column_name: "Status"}} }

        it "gives the code target_column_not_in_schema, with the columns and the table" do
          expect { result }.to raise_error(Pipeforge::InvalidMappedColumnsError) do |error|
            expect(error.errors.map { |entry| entry.except(:message) }).to eq(
              [{code: :target_column_not_in_schema, source_column_name: "Status", target_column_name: "state", table_name: "records"}]
            )
          end
        end

        it "names the source column, the target column and the table in the message" do
          expect { result }.to raise_error(Pipeforge::InvalidMappedColumnsError, /state.*records/)
        end
      end

      context "with a required target column that has no entry" do
        let(:target_columns) { [build_target_column(name: "status", required: true), build_target_column(name: "code")] }
        let(:mapped_columns) { {"code" => {source_column_name: "Code"}} }

        it "gives the code required_column_unmapped, with the target column" do
          expect { result }.to raise_error(Pipeforge::InvalidMappedColumnsError) do |error|
            expect(error.errors.map { |entry| entry.slice(:code, :target_column_name) }).to eq(
              [{code: :required_column_unmapped, target_column_name: "status"}]
            )
          end
        end
      end

      context "in several columns" do
        let(:mapped_columns) do
          {"status" => {}, "nowhere" => {source_column_name: "Code"}, "note" => {source_column_name: "Note"}}
        end

        it "lists every error in one error, in order" do
          expect { result }.to raise_error(Pipeforge::InvalidMappedColumnsError) do |error|
            expect(error.errors.map { |entry| entry.slice(:code, :target_column_name) }).to eq(
              [
                {code: :column_missing_source_column, target_column_name: "status"},
                {code: :target_column_not_in_schema, target_column_name: "nowhere"}
              ]
            )
          end
        end
      end

      context "together with a column that is not in the file" do
        let(:mapped_columns) { {"status" => {}, "code" => {source_column_name: "Gone"}} }

        it "reports both in one error" do
          expect { result }.to raise_error(Pipeforge::InvalidMappedColumnsError) do |error|
            expect(error.errors.map { |entry| entry.slice(:code, :target_column_name) }).to eq(
              [
                {code: :column_missing_source_column, target_column_name: "status"},
                {code: :mapped_column_not_in_file, target_column_name: "code"}
              ]
            )
          end
        end
      end

      context "when the columns are checked" do
        let(:mapped_columns) { {"status" => {}} }

        it "does not create a column values analyzer" do
          allow(Pipeforge::ColumnValueAnalyzer).to receive(:call).and_call_original

          expect { result }.to raise_error(Pipeforge::InvalidMappedColumnsError)
          expect(Pipeforge::ColumnValueAnalyzer).not_to have_received(:call)
        end
      end
    end

    context "with a value mapping whose keys are not text" do
      let(:source_io) { csv_io("Count\n1\n2\n") }
      let(:target_columns) { [build_target_column(name: "count", type: "integer")] }
      let(:mapped_columns) do
        {"count" => {source_column_name: "Count", value_mapping: {1 => "x", 2 => "20"}}}
      end

      it "applies the mapping, because the keys are turned into text" do
        # 1 maps to x, which does not fit an integer; 2 maps to 20, which fits.
        expect(result.column_summaries["count"].distinct_values).to have_attributes(compatible_count: 1, incompatible_count: 1)
      end

      it "returns the mapping with its keys as text" do
        expect(result.column_summaries["count"].value_mapping).to eq("1" => "x", "2" => "20")
      end

      it "leaves the entries of the caller as they were written" do
        expect { result }.not_to change { mapped_columns.inspect }
      end

      context "when two keys give the same text" do
        let(:mapped_columns) do
          {"count" => {source_column_name: "Count", value_mapping: {1 => "x", "1" => "20"}}}
        end

        it "makes them one key, and the later one is used" do
          expect(result.column_summaries["count"].value_mapping).to eq("1" => "20")
        end
      end
    end

    context "with a column that has no value mapping" do
      let(:source_io) { csv_io("Count\n1\n") }
      let(:target_columns) { [build_target_column(name: "count", type: "integer")] }
      let(:mapped_columns) { {"count" => {source_column_name: "Count"}} }

      it "returns an empty value mapping for it" do
        expect(result.column_summaries["count"].value_mapping).to eq({})
      end
    end

    context "with a value mapping on a column" do
      let(:target_columns) { [build_target_column(name: "status", type: "integer")] }
      let(:mapped_columns) { {"status" => {source_column_name: "Status", value_mapping: value_mapping}} }
      let(:value_mapping) { {"Active" => "1", "A" => "x"} }

      it "measures the values as the values they map to" do
        expect(result.column_summaries["status"].distinct_values).to have_attributes(compatible_count: 4, incompatible_count: 3)
      end

      it "returns the value mapping with the column" do
        expect(result.column_summaries["status"].value_mapping).to eq(value_mapping)
      end

      context "when it is called again with an edited value mapping" do
        let(:edited_mapped_columns) do
          {
            "status" => {
              source_column_name: "Status",
              value_mapping: {"Active" => "1", "INACTIVE" => "0", "A" => "2"}
            }
          }
        end

        it "shows the facts again, now that every value fits" do
          edited_result = engine.analyze_column_values(mapped_columns: edited_mapped_columns)

          expect(edited_result.column_summaries["status"].distinct_values).to have_attributes(compatible_count: 7, incompatible_count: 0)
        end
      end
    end
  end

  describe "the target of the target model" do
    let(:source_io) { csv_io("Status,Code\n1,2\n") }
    let(:target_columns) { [build_target_column(name: "status"), build_target_column(name: "code")] }

    it "is built once, however many times the stages use it" do
      engine.analyze_headers
      engine.analyze_column_values(mapped_columns: {"status" => {source_column_name: "Status"}})
      engine.analyze_column_values(mapped_columns: {"code" => {source_column_name: "Code"}})
      engine.run(mode: :dry_run, mapped_columns: {"status" => {source_column_name: "Status"}})

      expect(target_class).to have_received(:new).with(target_model_name: "Record").once
    end

    it "gives its schema once, however many times the stages are called" do
      allow(target).to receive(:schema).and_call_original

      engine.analyze_headers
      engine.analyze_column_values(mapped_columns: {"status" => {source_column_name: "Status"}})
      engine.analyze_column_values(mapped_columns: {"code" => {source_column_name: "Code"}})

      expect(target).to have_received(:schema).once
    end

    context "when building it fails" do
      let(:target_error) do
        Pipeforge::TargetSchemaError.single(code: :target_table_not_found, message: "no such table", table_name: "records")
      end

      it "builds it again on the next call" do
        allow(target_class).to receive(:new).and_raise(target_error)
        expect { engine.analyze_column_values(mapped_columns: {"status" => {source_column_name: "Status"}}) }
          .to raise_error(Pipeforge::TargetSchemaError)

        allow(target_class).to receive(:new).and_return(target)

        expect(engine.analyze_column_values(mapped_columns: {"status" => {source_column_name: "Status"}}).column_summaries.keys).to eq(["status"])
      end
    end
  end
end
