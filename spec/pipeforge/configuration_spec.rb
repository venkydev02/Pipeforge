# frozen_string_literal: true

RSpec.describe Pipeforge::Configuration do
  # Writes the text to a temporary engine.yml and builds a configuration from it.
  def configuration_from(yaml)
    Tempfile.create(["engine", ".yml"]) do |file|
      file.write(yaml)
      file.flush
      described_class.new(path: file.path)
    end
  end

  it "reads every known setting from the engine section" do
    config = configuration_from(<<~YAML)
      version: "1.0"
      engine:
        execution:
          batch_size: 500
        source:
          encoding: "windows-1252"
          distinct_values_cap: 50
    YAML

    expect([config.execution.batch_size, config.source.encoding, config.source.distinct_values_cap])
      .to eq([500, "windows-1252", 50])
  end

  it "keeps the defaults for what the file does not mention" do
    config = configuration_from("engine:\n  execution:\n    batch_size: 500\n")

    expect(config.execution.batch_size).to eq(500)
    expect(config.source.encoding).to eq("UTF-8")
    expect(config.source.distinct_values_cap).to eq(1000)
  end

  it "keeps the other setting of a section when the file sets only one" do
    config = configuration_from("engine:\n  source:\n    distinct_values_cap: 50\n")

    expect(config.source.encoding).to eq("UTF-8")
  end

  it "has all defaults for an empty file, and for a file with no engine section" do
    [configuration_from(""), configuration_from("version: '1.0'\n")].each do |config|
      expect(config.execution.batch_size).to eq(2000)
      expect(config.source.distinct_values_cap).to eq(1000)
    end
  end

  it "no longer has a recommendation section" do
    expect { configuration_from("engine:\n  recommendation:\n    distinct_values_cap: 50\n") }
      .to raise_error(Pipeforge::ConfigurationError, /unknown section recommendation/)
  end

  it "remembers the path it was read from" do
    Tempfile.create(["engine", ".yml"]) do |file|
      expect(described_class.new(path: file.path).path).to eq(file.path)
    end
  end

  it "cannot be changed once built" do
    expect(configuration_from("").frozen?).to be(true)
    expect { configuration_from("").instance_variable_set(:@source, nil) }.to raise_error(FrozenError)
  end

  describe "a file that cannot be used" do
    it "names the path when the file does not exist" do
      expect { described_class.new(path: "no/such/engine.yml") }
        .to raise_error(Pipeforge::ConfigurationError, %r{configuration file not found: no/such/engine.yml})
    end

    it "says so when the file is not valid YAML" do
      expect { configuration_from("engine: [unclosed\n") }
        .to raise_error(Pipeforge::ConfigurationError, /not valid YAML/)
    end

    it "names the path when the path is a directory" do
      expect { described_class.new(path: Dir.tmpdir) }
        .to raise_error(Pipeforge::ConfigurationError, /configuration file not found/)
    end

    it "says so when the YAML uses a tag that is not allowed" do
      expect { configuration_from("engine: !ruby/object:Object {}\n") }
        .to raise_error(Pipeforge::ConfigurationError, /not valid YAML/)
    end

    context "when the file is not a mapping at the top level" do
      {"a list" => "- a\n- b\n", "a single word" => "hello\n", "a number" => "42\n"}.each do |description, yaml|
        it "raises our own error for #{description}" do
          expect { configuration_from(yaml) }
            .to raise_error(Pipeforge::ConfigurationError, /must hold a mapping at the top level/)
        end
      end
    end

    context "when engine is not a mapping of sections" do
      {"a list" => "engine:\n  - a\n", "a single word" => "engine: hello\n"}.each do |description, yaml|
        it "raises our own error for #{description}" do
          expect { configuration_from(yaml) }
            .to raise_error(Pipeforge::ConfigurationError, /engine in .* must be a mapping of sections/)
        end
      end
    end

    context "when a section is not a mapping of settings" do
      {"a number" => "engine:\n  execution: 5\n", "a list" => "engine:\n  execution:\n    - a\n"}.each do |description, yaml|
        it "raises our own error for #{description}" do
          expect { configuration_from(yaml) }
            .to raise_error(Pipeforge::ConfigurationError, /section execution of .* must be a mapping of settings/)
        end
      end
    end

    context "when engine or a section has nothing under it" do
      it "keeps the defaults" do
        expect(configuration_from("engine:\n  execution:\n").execution.batch_size).to eq(2000)
      end
    end

    it "names an unknown section" do
      expect { configuration_from("engine:\n  loging:\n    level: info\n") }
        .to raise_error(Pipeforge::ConfigurationError, /unknown section loging/)
    end

    it "names an unknown setting and its section" do
      expect { configuration_from("engine:\n  execution:\n    batch_sise: 10\n") }
        .to raise_error(Pipeforge::ConfigurationError, /unknown setting in section execution.*batch_sise/)
    end
  end
end
