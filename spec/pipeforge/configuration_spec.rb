# frozen_string_literal: true

RSpec.describe Pipeforge::Configuration do
  subject(:configuration) { described_class.new(path: path) }

  let(:path) { yaml_file(yaml) }
  let(:yaml) { "" }

  describe "#execution, #source" do
    context "with every known setting in the engine section" do
      let(:yaml) do
        <<~YAML
          version: "1.0"
          engine:
            execution:
              batch_size: 500
            source:
              encoding: "windows-1252"
              distinct_values_cap: 50
        YAML
      end

      it "reads the batch size" do
        expect(configuration.execution.batch_size).to eq(500)
      end

      it "reads the encoding" do
        expect(configuration.source.encoding).to eq("windows-1252")
      end

      it "reads the distinct values cap" do
        expect(configuration.source.distinct_values_cap).to eq(50)
      end
    end

    context "with only one setting" do
      let(:yaml) { "engine:\n  execution:\n    batch_size: 500\n" }

      it "reads it" do
        expect(configuration.execution.batch_size).to eq(500)
      end

      it "keeps the defaults of the settings the file does not mention" do
        expect(configuration.source).to have_attributes(encoding: "UTF-8", distinct_values_cap: 1000)
      end
    end

    context "with only one setting of a section" do
      let(:yaml) { "engine:\n  source:\n    distinct_values_cap: 50\n" }

      it "keeps the default of the other setting of that section" do
        expect(configuration.source.encoding).to eq("UTF-8")
      end
    end

    {
      "an empty file" => "",
      "a file with no engine section" => "version: '1.0'\n",
      "an engine section with nothing under it" => "engine:\n",
      "a section with nothing under it" => "engine:\n  execution:\n"
    }.each do |description, text|
      context "with #{description}" do
        let(:yaml) { text }

        it "uses every default" do
          expect(configuration).to have_attributes(
            execution: have_attributes(batch_size: 2000),
            source: have_attributes(encoding: "UTF-8", distinct_values_cap: 1000)
          )
        end
      end
    end
  end

  describe "#path" do
    it "is the path the settings were read from" do
      expect(configuration.path).to eq(path)
    end
  end

  describe "immutability" do
    it "is frozen once built" do
      expect(configuration).to be_frozen
    end

    it "cannot be changed" do
      expect { configuration.instance_variable_set(:@source, nil) }.to raise_error(FrozenError)
    end
  end

  describe ".new" do
    shared_examples "a file the engine refuses" do |message|
      it "raises ConfigurationError, saying what is wrong" do
        expect { configuration }.to raise_error(Pipeforge::ConfigurationError, message)
      end
    end

    context "when the file does not exist" do
      let(:path) { "no/such/engine.yml" }

      include_examples "a file the engine refuses", %r{configuration file not found: no/such/engine.yml}
    end

    context "when the path is a directory" do
      let(:path) { Dir.tmpdir }

      include_examples "a file the engine refuses", /configuration file not found/
    end

    context "when the file is not valid YAML" do
      let(:yaml) { "engine: [unclosed\n" }

      include_examples "a file the engine refuses", /not valid YAML/
    end

    context "when the YAML uses a tag that is not allowed" do
      let(:yaml) { "engine: !ruby/object:Object {}\n" }

      include_examples "a file the engine refuses", /not valid YAML/
    end

    {"a list" => "- a\n- b\n", "a single word" => "hello\n", "a number" => "42\n"}.each do |description, text|
      context "when the file is #{description}, not a mapping" do
        let(:yaml) { text }

        include_examples "a file the engine refuses", /must hold a mapping at the top level/
      end
    end

    {"a list" => "engine:\n  - a\n", "a single word" => "engine: hello\n"}.each do |description, text|
      context "when engine is #{description}, not a mapping of sections" do
        let(:yaml) { text }

        include_examples "a file the engine refuses", /engine in .* must be a mapping of sections/
      end
    end

    {"a number" => "engine:\n  execution: 5\n", "a list" => "engine:\n  execution:\n    - a\n"}.each do |description, text|
      context "when a section is #{description}, not a mapping of settings" do
        let(:yaml) { text }

        include_examples "a file the engine refuses", /section execution of .* must be a mapping of settings/
      end
    end

    context "with a section it does not know" do
      let(:yaml) { "engine:\n  loging:\n    level: info\n" }

      include_examples "a file the engine refuses", /unknown section loging/
    end

    context "with a setting it does not know" do
      let(:yaml) { "engine:\n  execution:\n    batch_sise: 10\n" }

      include_examples "a file the engine refuses", /unknown setting in section execution.*batch_sise/
    end
  end
end
