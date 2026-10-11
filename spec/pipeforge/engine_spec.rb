# frozen_string_literal: true

RSpec.describe Pipeforge::Engine do
  let(:source_path) { File.expand_path("../fixtures/source/statuses.csv", __dir__) }

  # Writes the text to a temporary engine.yml and yields its path (the file is removed after).
  def with_config(yaml = "version: '1.0'\n")
    Tempfile.create(["engine", ".yml"]) do |file|
      file.write(yaml)
      file.flush
      yield file.path
    end
  end

  describe ".new" do
    it "loads the configuration from the file at the given path" do
      with_config("engine:\n  source:\n    distinct_values_cap: 3\n") do |config_path|
        config = described_class.new(config_path: config_path, source_path: source_path).config

        expect(config.source.distinct_values_cap).to eq(3)
        expect(config.execution.batch_size).to eq(2000) # not in the file: keeps its default
      end
    end

    it "keeps both paths it was given" do
      with_config do |config_path|
        engine = described_class.new(config_path: config_path, source_path: source_path)

        expect(engine.source_path).to eq(source_path)
        expect(engine.config.path).to eq(config_path)
      end
    end

    it "needs both paths: they are never searched for" do
      with_config do |config_path|
        expect { described_class.new }.to raise_error(ArgumentError)
        expect { described_class.new(config_path: config_path) }.to raise_error(ArgumentError)
      end
    end

    it "stops with our own error when the configuration file does not exist" do
      expect { described_class.new(config_path: "no/such/engine.yml", source_path: source_path) }
        .to raise_error(Pipeforge::ConfigurationError, %r{configuration file not found: no/such/engine.yml})
    end

    it "stops with our own error for a setting it does not know" do
      with_config("engine:\n  execution:\n    batch_sise: 10\n") do |config_path|
        expect { described_class.new(config_path: config_path, source_path: source_path) }
          .to raise_error(Pipeforge::ConfigurationError, /unknown setting.*batch_sise/)
      end
    end

    it "stops with our own error when the source file does not exist" do
      with_config do |config_path|
        expect { described_class.new(config_path: config_path, source_path: "no/such/file.csv") }
          .to raise_error(Pipeforge::Source::MissingSourceError, %r{not found or not readable: no/such/file.csv})
      end
    end

    it "stops with our own error when the source is a directory" do
      with_config do |config_path|
        expect { described_class.new(config_path: config_path, source_path: File.dirname(source_path)) }
          .to raise_error(Pipeforge::Source::MissingSourceError)
      end
    end
  end

  describe "#analyze_values" do
    let(:column_mapping) do
      {
        "Status" => {target_column: "status", type: "string"},
        "Code" => {target_column: "code", type: "string"},
        "Note" => {target_column: "note", type: "string"}
      }
    end

    def engine_for(config_path)
      described_class.new(config_path: config_path, source_path: source_path)
    end

    it "returns what the mapped columns contain, using the loaded configuration" do
      with_config("engine:\n  source:\n    distinct_values_cap: 2\n") do |config_path|
        result = engine_for(config_path).analyze_values(column_mapping: column_mapping)

        expect(result.source_identifier).to eq(source_path)
        expect(result.columns.keys).to eq(%w[Status Code Note])
        expect(result.columns["Code"].target_column).to eq("code")
        expect(result.columns["Code"].distinct_values[:compatible].values.size).to eq(2)
      end
    end

    it "measures only the mapped columns" do
      with_config do |config_path|
        result = engine_for(config_path).analyze_values(
          column_mapping: {"Code" => {target_column: "code", type: "string"}}
        )

        expect(result.columns.keys).to eq(["Code"])
      end
    end

    it "stops with our own error when a mapped column is not in the file" do
      with_config do |config_path|
        engine = engine_for(config_path)

        expect {
          engine.analyze_values(column_mapping: {"Nope" => {target_column: "status", type: "string"}})
        }.to raise_error(Pipeforge::Source::MissingColumnError, /Nope/)
      end
    end

    it "can be called again without passing the source" do
      with_config do |config_path|
        engine = engine_for(config_path)

        first_result = engine.analyze_values(column_mapping: column_mapping)
        second_result = engine.analyze_values(column_mapping: column_mapping)

        expect(second_result.to_h).to eq(first_result.to_h)
      end
    end
  end
end
