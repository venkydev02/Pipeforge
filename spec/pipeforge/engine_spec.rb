# frozen_string_literal: true

RSpec.describe Pipeforge::Engine do
  subject(:engine) { described_class.new(config_path: config_path, source_path: source_path) }

  let(:config_path) { yaml_file(yaml) }
  let(:yaml) { "version: '1.0'\n" }
  # Status: Active x4 (one written " Active "), INACTIVE x2, A x1. Code: seven different values.
  let(:source_path) { File.expand_path("../fixtures/source/statuses.csv", __dir__) }

  describe ".new" do
    it "keeps the source path it was given" do
      expect(engine.source_path).to eq(source_path)
    end

    it "keeps the path of the configuration file" do
      expect(engine.config.path).to eq(config_path)
    end

    context "with settings in the configuration file" do
      let(:yaml) { "engine:\n  source:\n    distinct_values_cap: 3\n" }

      it "loads them" do
        expect(engine.config.source.distinct_values_cap).to eq(3)
      end

      it "keeps the defaults for the settings that are not in the file" do
        expect(engine.config.execution.batch_size).to eq(2000)
      end
    end

    context "when the configuration file does not exist" do
      let(:config_path) { "no/such/engine.yml" }

      it "stops with our own error" do
        expect { engine }.to raise_error(Pipeforge::ConfigurationError, %r{configuration file not found: no/such/engine.yml})
      end
    end

    context "with a setting it does not know" do
      let(:yaml) { "engine:\n  execution:\n    batch_sise: 10\n" }

      it "stops with our own error, naming the setting" do
        expect { engine }.to raise_error(Pipeforge::ConfigurationError, /unknown setting.*batch_sise/)
      end
    end

    context "when the source file does not exist" do
      let(:source_path) { "no/such/file.csv" }

      it "stops with our own error" do
        expect { engine }.to raise_error(
          Pipeforge::Source::MissingSourceError, %r{not found or not readable: no/such/file.csv}
        )
      end
    end

    context "when the source is a directory" do
      let(:source_path) { File.dirname(File.expand_path("../fixtures/source/statuses.csv", __dir__)) }

      it "stops with our own error" do
        expect { engine }.to raise_error(Pipeforge::Source::MissingSourceError)
      end
    end
  end

  describe "#analyze_values" do
    subject(:result) { engine.analyze_values(mapped_columns: mapped_columns) }

    let(:mapped_columns) do
      {
        "Status" => {target_column: "status", type: "string"},
        "Code" => {target_column: "code", type: "string"},
        "Note" => {target_column: "note", type: "string"}
      }
    end

    it "names the source file" do
      expect(result.source_identifier).to eq(source_path)
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

    context "with a cap on the distinct values in the configuration file" do
      let(:yaml) { "engine:\n  source:\n    distinct_values_cap: 2\n" }

      it "lists at most that many values per list" do
        expect(result.columns["Code"].distinct_values[:compatible].values.size).to eq(2)
      end
    end

    context "when only some columns are mapped" do
      let(:mapped_columns) { {"Code" => {target_column: "code", type: "string"}} }

      it "measures only those columns" do
        expect(result.columns.keys).to eq(["Code"])
      end
    end

    context "when a mapped column is not in the file" do
      let(:mapped_columns) { {"Nope" => {target_column: "status", type: "string"}} }

      it "stops with our own error, naming the column" do
        expect { result }.to raise_error(Pipeforge::Source::MissingColumnError, /Nope/)
      end
    end

    context "with a value mapping on a column" do
      let(:mapped_columns) do
        {"Status" => {target_column: "status", type: "integer", value_mapping: value_mapping}}
      end
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
              type: "integer",
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
