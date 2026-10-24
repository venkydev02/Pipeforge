# frozen_string_literal: true

RSpec.describe Pipeforge::Configuration do
  # Loading reads config/pipeforge.yml of the project. Each example runs in an empty project
  # directory that holds the file given as +yaml+ (nil: no file); the module is the subject once
  # it has loaded.
  subject(:configuration) do
    described_class.load
    described_class
  end

  let(:yaml) { "" }

  around { |example| in_project_directory(config: yaml) { example.run } }

  # The YAML of a file that sets one setting of one section.
  def setting_yaml(section:, setting:, value:)
    "engine:\n  #{section}:\n    #{setting}: #{value}\n"
  end

  shared_examples "every default" do
    it "uses the default batch size" do
      expect(configuration.execution.batch_size).to eq(2000)
    end

    it "uses the default distinct values cap" do
      expect(configuration.source.distinct_values_cap).to eq(1000)
    end

    it "turns the source fingerprint off" do
      expect(configuration.source.fingerprint).to eq(false)
    end

    it "uses the default inclusion threshold" do
      expect(configuration.recommendation.inclusion_threshold).to eq(55)
    end

    it "uses the default reorder penalty" do
      expect(configuration.recommendation.reorder_penalty).to eq(10)
    end
  end

  shared_examples "a file the engine refuses" do |code, message|
    it "raises ConfigurationError, saying what is wrong" do
      expect { configuration }.to raise_error(Pipeforge::ConfigurationError, message)
    end

    it "gives the code #{code}" do
      expect { configuration }.to raise_error(Pipeforge::ConfigurationError) do |error|
        expect(error.codes).to eq([code])
      end
    end
  end

  describe ".execution and .source" do
    context "with every known setting in the engine section" do
      let(:yaml) do
        <<~YAML
          version: "1.0"
          engine:
            execution:
              batch_size: 500
            source:
              distinct_values_cap: 50
        YAML
      end

      it "reads the batch size" do
        expect(configuration.execution.batch_size).to eq(500)
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
        expect(configuration.source).to have_attributes(distinct_values_cap: 1000, fingerprint: false)
      end
    end

    context "with only one setting of a section" do
      let(:yaml) { "engine:\n  source:\n    distinct_values_cap: 50\n" }

      it "keeps the default of the other setting of that section" do
        expect(configuration.source.fingerprint).to eq(false)
      end
    end

    context "with an empty file" do
      let(:yaml) { "" }

      include_examples "every default"
    end

    context "with a file that has no engine section" do
      let(:yaml) { "version: '1.0'\n" }

      include_examples "every default"
    end

    context "with an engine section that has nothing under it" do
      let(:yaml) { "engine:\n" }

      include_examples "every default"
    end

    context "with a section that has nothing under it" do
      let(:yaml) { "engine:\n  execution:\n" }

      include_examples "every default"
    end
  end

  describe ".path" do
    it "is the conventional path the settings were read from" do
      expect(configuration.path).to eq("config/pipeforge.yml")
    end
  end

  describe "the settings loaded when the gem was required" do
    let(:yaml) { nil }

    it "come from config/pipeforge.yml, by convention" do
      expect(described_class::DEFAULT_PATH).to eq("config/pipeforge.yml")
    end

    it "are the defaults when the project has no such file" do
      expect(described_class.execution.batch_size).to eq(2000)
    end

    it "give each section by name" do
      expect(described_class.source.distinct_values_cap).to eq(1000)
      expect(described_class.recommendation.inclusion_threshold).to eq(55)
    end
  end

  describe ".load when a later load fails" do
    let(:yaml) { "engine:\n  execution:\n    batch_size: 7\n" }

    it "keeps the settings it had" do
      described_class.load
      File.write(described_class::DEFAULT_PATH, "engine: [unclosed\n")

      expect { described_class.load }.to raise_error(Pipeforge::ConfigurationError)
      expect(described_class.execution.batch_size).to eq(7)
    end
  end

  describe ".load" do
    context "when the file does not exist" do
      let(:yaml) { nil }

      include_examples "every default"
    end

    context "when the path is a directory" do
      let(:yaml) { nil }

      before { FileUtils.mkdir_p(described_class::DEFAULT_PATH) }

      include_examples "every default"
    end

    context "when the file is not valid YAML" do
      let(:yaml) { "engine: [unclosed\n" }

      include_examples "a file the engine refuses", :config_file_not_valid_yaml, /not valid YAML/
    end

    context "when the YAML uses a tag that is not allowed" do
      let(:yaml) { "engine: !ruby/object:Object {}\n" }

      include_examples "a file the engine refuses", :config_file_not_valid_yaml, /not valid YAML/
    end

    context "when the file is a list, not name: value entries" do
      let(:yaml) { "- a\n- b\n" }

      include_examples "a file the engine refuses", :config_file_not_name_value_entries,
        /must be made of name: value entries at the top level/
    end

    context "when the file is a single word, not name: value entries" do
      let(:yaml) { "hello\n" }

      include_examples "a file the engine refuses", :config_file_not_name_value_entries,
        /must be made of name: value entries at the top level/
    end

    context "when the file is a number, not name: value entries" do
      let(:yaml) { "42\n" }

      include_examples "a file the engine refuses", :config_file_not_name_value_entries,
        /must be made of name: value entries at the top level/
    end

    context "when engine is a list, not sections" do
      let(:yaml) { "engine:\n  - a\n" }

      include_examples "a file the engine refuses", :engine_not_sections,
        /engine must hold sections, each written as a name/
    end

    context "when engine is a single word, not sections" do
      let(:yaml) { "engine: hello\n" }

      include_examples "a file the engine refuses", :engine_not_sections,
        /engine must hold sections, each written as a name/
    end

    context "when a section is a number, not settings" do
      let(:yaml) { "engine:\n  execution: 5\n" }

      include_examples "a file the engine refuses", :section_not_settings,
        /section execution must hold settings, each written as name: value/
    end

    context "when a section is a list, not settings" do
      let(:yaml) { "engine:\n  execution:\n    - a\n" }

      include_examples "a file the engine refuses", :section_not_settings,
        /section execution must hold settings, each written as name: value/
    end

    context "with a section it does not know" do
      let(:yaml) { "engine:\n  loging:\n    level: info\n" }

      include_examples "a file the engine refuses", :unknown_section, /unknown section loging/

      it "says which section" do
        expect { configuration }.to raise_error(Pipeforge::ConfigurationError) do |error|
          expect(error.errors.first).to include(section: "loging")
        end
      end
    end

    context "with a setting it does not know" do
      let(:yaml) { "engine:\n  execution:\n    batch_sise: 10\n" }

      include_examples "a file the engine refuses", :unknown_setting,
        /unknown setting batch_sise in section execution/

      it "says which section and which setting" do
        expect { configuration }.to raise_error(Pipeforge::ConfigurationError) do |error|
          expect(error.errors.first).to include(section: "execution", setting: "batch_sise")
        end
      end
    end

    describe "execution.batch_size" do
      context "set to text" do
        let(:yaml) { setting_yaml(section: "execution", setting: "batch_size", value: "abc") }

        include_examples "a file the engine refuses", :setting_not_positive_whole_number,
          /execution\.batch_size must be a whole number of at least 1, got "abc"/

        it "says which setting and which value" do
          expect { configuration }.to raise_error(Pipeforge::ConfigurationError) do |error|
            expect(error.errors.first).to include(setting: "execution.batch_size", value: "abc")
          end
        end
      end

      context "set to a decimal" do
        let(:yaml) { setting_yaml(section: "execution", setting: "batch_size", value: "1.5") }

        include_examples "a file the engine refuses", :setting_not_positive_whole_number,
          /execution\.batch_size must be a whole number of at least 1/
      end

      context "set to zero" do
        let(:yaml) { setting_yaml(section: "execution", setting: "batch_size", value: "0") }

        include_examples "a file the engine refuses", :setting_not_positive_whole_number,
          /execution\.batch_size must be a whole number of at least 1/
      end

      context "set to a negative number" do
        let(:yaml) { setting_yaml(section: "execution", setting: "batch_size", value: "-5") }

        include_examples "a file the engine refuses", :setting_not_positive_whole_number,
          /execution\.batch_size must be a whole number of at least 1/
      end

      context "set to true" do
        let(:yaml) { setting_yaml(section: "execution", setting: "batch_size", value: "true") }

        include_examples "a file the engine refuses", :setting_not_positive_whole_number,
          /execution\.batch_size must be a whole number of at least 1/
      end

      context "set to nothing" do
        let(:yaml) { setting_yaml(section: "execution", setting: "batch_size", value: "") }

        include_examples "a file the engine refuses", :setting_not_positive_whole_number,
          /execution\.batch_size must be a whole number of at least 1/
      end

      context "set to a list" do
        let(:yaml) { setting_yaml(section: "execution", setting: "batch_size", value: "[1]") }

        include_examples "a file the engine refuses", :setting_not_positive_whole_number,
          /execution\.batch_size must be a whole number of at least 1/
      end

      context "set to 1" do
        let(:yaml) { setting_yaml(section: "execution", setting: "batch_size", value: "1") }

        it "is accepted" do
          expect(configuration.execution.batch_size).to eq(1)
        end
      end

      context "set to 100000" do
        let(:yaml) { setting_yaml(section: "execution", setting: "batch_size", value: "100000") }

        it "is accepted" do
          expect(configuration.execution.batch_size).to eq(100_000)
        end
      end
    end

    describe "recommendation.inclusion_threshold" do
      context "set to 80" do
        let(:yaml) { setting_yaml(section: "recommendation", setting: "inclusion_threshold", value: "80") }

        it "reads it" do
          expect(configuration.recommendation.inclusion_threshold).to eq(80)
        end
      end

      context "set to 1" do
        let(:yaml) { setting_yaml(section: "recommendation", setting: "inclusion_threshold", value: "1") }

        it "reads it" do
          expect(configuration.recommendation.inclusion_threshold).to eq(1)
        end
      end

      context "set to 100" do
        let(:yaml) { setting_yaml(section: "recommendation", setting: "inclusion_threshold", value: "100") }

        it "reads it" do
          expect(configuration.recommendation.inclusion_threshold).to eq(100)
        end
      end

      context "set to 0" do
        let(:yaml) { setting_yaml(section: "recommendation", setting: "inclusion_threshold", value: "0") }

        include_examples "a file the engine refuses", :setting_not_positive_whole_number,
          /recommendation\.inclusion_threshold must be a whole number of at least 1, got 0/
      end

      context "set to a negative number" do
        let(:yaml) { setting_yaml(section: "recommendation", setting: "inclusion_threshold", value: "-1") }

        include_examples "a file the engine refuses", :setting_not_positive_whole_number,
          /recommendation\.inclusion_threshold must be a whole number of at least 1, got -1/
      end

      context "set to a decimal" do
        let(:yaml) { setting_yaml(section: "recommendation", setting: "inclusion_threshold", value: "55.5") }

        include_examples "a file the engine refuses", :setting_not_positive_whole_number,
          /recommendation\.inclusion_threshold must be a whole number of at least 1/
      end

      context "set to text" do
        let(:yaml) { setting_yaml(section: "recommendation", setting: "inclusion_threshold", value: "high") }

        include_examples "a file the engine refuses", :setting_not_positive_whole_number,
          /recommendation\.inclusion_threshold must be a whole number of at least 1, got "high"/
      end
    end

    describe "recommendation.reorder_penalty" do
      context "set to 25" do
        let(:yaml) { setting_yaml(section: "recommendation", setting: "reorder_penalty", value: "25") }

        it "reads it" do
          expect(configuration.recommendation.reorder_penalty).to eq(25)
        end
      end

      context "set to 101" do
        let(:yaml) { setting_yaml(section: "recommendation", setting: "reorder_penalty", value: "101") }

        include_examples "a file the engine refuses", :setting_not_whole_number_0_to_100,
          /recommendation\.reorder_penalty must be a whole number from 0 to 100, got 101/
      end
    end

    describe "source.fingerprint" do
      context "set to true" do
        let(:yaml) { setting_yaml(section: "source", setting: "fingerprint", value: "true") }

        it "reads it" do
          expect(configuration.source.fingerprint).to eq(true)
        end
      end

      context "set to a word that is not true or false" do
        let(:yaml) { setting_yaml(section: "source", setting: "fingerprint", value: "maybe") }

        include_examples "a file the engine refuses", :setting_not_true_or_false,
          /source\.fingerprint must be true or false, got "maybe"/
      end
    end

    describe "source.distinct_values_cap" do
      context "set to text" do
        let(:yaml) { setting_yaml(section: "source", setting: "distinct_values_cap", value: "many") }

        include_examples "a file the engine refuses", :setting_not_positive_whole_number,
          /source\.distinct_values_cap must be a whole number of at least 1, got "many"/
      end

      context "set to a decimal" do
        let(:yaml) { setting_yaml(section: "source", setting: "distinct_values_cap", value: "2.5") }

        include_examples "a file the engine refuses", :setting_not_positive_whole_number,
          /source\.distinct_values_cap must be a whole number of at least 1/
      end

      context "set to zero" do
        let(:yaml) { setting_yaml(section: "source", setting: "distinct_values_cap", value: "0") }

        include_examples "a file the engine refuses", :setting_not_positive_whole_number,
          /source\.distinct_values_cap must be a whole number of at least 1/
      end

      context "set to a negative number" do
        let(:yaml) { setting_yaml(section: "source", setting: "distinct_values_cap", value: "-1") }

        include_examples "a file the engine refuses", :setting_not_positive_whole_number,
          /source\.distinct_values_cap must be a whole number of at least 1/
      end

      context "set to true" do
        let(:yaml) { setting_yaml(section: "source", setting: "distinct_values_cap", value: "true") }

        include_examples "a file the engine refuses", :setting_not_positive_whole_number,
          /source\.distinct_values_cap must be a whole number of at least 1/
      end

      context "set to nothing" do
        let(:yaml) { setting_yaml(section: "source", setting: "distinct_values_cap", value: "") }

        include_examples "a file the engine refuses", :setting_not_positive_whole_number,
          /source\.distinct_values_cap must be a whole number of at least 1/
      end

      context "set to a list" do
        let(:yaml) { setting_yaml(section: "source", setting: "distinct_values_cap", value: "[1]") }

        include_examples "a file the engine refuses", :setting_not_positive_whole_number,
          /source\.distinct_values_cap must be a whole number of at least 1/
      end

      context "set to 1" do
        let(:yaml) { setting_yaml(section: "source", setting: "distinct_values_cap", value: "1") }

        it "is accepted" do
          expect(configuration.source.distinct_values_cap).to eq(1)
        end
      end

      context "set to 500" do
        let(:yaml) { setting_yaml(section: "source", setting: "distinct_values_cap", value: "500") }

        it "is accepted" do
          expect(configuration.source.distinct_values_cap).to eq(500)
        end
      end
    end

    describe "when there are several errors" do
      context "with a wrong value, an unknown setting and an unknown section" do
        let(:yaml) do
          <<~YAML
            engine:
              execution:
                batch_size: abc
                batch_sise: 10
              source:
                fingerprint: maybe
              loging:
                level: info
          YAML
        end

        it "reports all of them in one error" do
          expect { configuration }.to raise_error(Pipeforge::ConfigurationError, /has 4 errors/)
        end

        it "lists each error on its own line" do
          expect { configuration }.to raise_error(Pipeforge::ConfigurationError) do |error|
            expect(error.message.lines.map(&:strip)).to include(
              "- unknown section loging",
              "- unknown setting batch_sise in section execution",
              "- execution.batch_size must be a whole number of at least 1, got \"abc\"",
              "- source.fingerprint must be true or false, got \"maybe\""
            )
          end
        end

        it "starts with the file, so the consumer knows which file to open" do
          expect { configuration }.to raise_error(Pipeforge::ConfigurationError).with_message(a_string_starting_with("#{described_class::DEFAULT_PATH} has 4 errors:"))
        end

        it "has one entry for each, in the order they are found" do
          expect { configuration }.to raise_error(Pipeforge::ConfigurationError) do |error|
            expect(error.codes).to eq(
              %i[unknown_section unknown_setting setting_not_positive_whole_number setting_not_true_or_false]
            )
          end
        end
      end

      context "with a wrong value in each of two sections" do
        let(:yaml) { "engine:\n  execution:\n    batch_size: 0\n  source:\n    distinct_values_cap: -1\n" }

        it "reports both" do
          expect { configuration }.to raise_error(
            Pipeforge::ConfigurationError, /execution\.batch_size.*source\.distinct_values_cap/m
          )
        end
      end

      context "with a section that is not settings next to a section with a wrong value" do
        let(:yaml) { "engine:\n  execution: 5\n  source:\n    fingerprint: maybe\n" }

        it "still checks the other section" do
          expect { configuration }.to raise_error(
            Pipeforge::ConfigurationError, /section execution must hold settings.*source\.fingerprint must be true or false/m
          )
        end
      end

      context "with an unknown setting next to a wrong value in the same section" do
        let(:yaml) { "engine:\n  source:\n    colour: red\n    distinct_values_cap: 0\n" }

        it "reports both, because the known settings are still checked" do
          expect { configuration }.to raise_error(
            Pipeforge::ConfigurationError, /unknown setting colour in section source.*source\.distinct_values_cap/m
          )
        end
      end

      context "with one error only" do
        let(:yaml) { "engine:\n  execution:\n    batch_size: abc\n" }

        it "gives the sentence, with no list" do
          expect { configuration }.to raise_error(
            Pipeforge::ConfigurationError,
            "#{described_class::DEFAULT_PATH}: execution.batch_size must be a whole number of at least 1, got \"abc\""
          )
        end
      end

      context "with a file that cannot be read at all" do
        let(:yaml) { "- a\n- b\n" }

        it "stops at once, with only that error" do
          expect { configuration }.to raise_error(
            Pipeforge::ConfigurationError, "#{described_class::DEFAULT_PATH}: must be made of name: value entries at the top level"
          )
        end
      end
    end
  end
end
