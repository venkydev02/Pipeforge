# frozen_string_literal: true

RSpec.describe Pipeforge::Error do
  describe "the errors the engine raises on purpose" do
    it "includes ConfigurationError" do
      expect(Pipeforge::ConfigurationError.ancestors).to include(described_class)
    end

    it "includes IncompleteColumnsError" do
      expect(Pipeforge::IncompleteColumnsError.ancestors).to include(described_class)
    end

    it "includes Source::MissingSourceError" do
      expect(Pipeforge::Source::MissingSourceError.ancestors).to include(described_class)
    end

    it "includes Source::EmptySourceError" do
      expect(Pipeforge::Source::EmptySourceError.ancestors).to include(described_class)
    end

    it "includes Source::MissingColumnError" do
      expect(Pipeforge::Source::MissingColumnError.ancestors).to include(described_class)
    end

    it "includes Source::MalformedSourceError" do
      expect(Pipeforge::Source::MalformedSourceError.ancestors).to include(described_class)
    end
  end

  describe ".single" do
    subject(:error) do
      Pipeforge::ConfigurationError.single(code: :unknown_section, message: "unknown section loging", section: "loging")
    end

    it "is an error of the class it is called on" do
      expect(error).to be_a(Pipeforge::ConfigurationError)
    end

    it "has the message for a person" do
      expect(error.message).to eq("unknown section loging")
    end

    it "has one entry with the code, the message and the fields that locate it" do
      expect(error.errors).to eq(
        [{code: :unknown_section, message: "unknown section loging", section: "loging"}]
      )
    end
  end

  describe "#codes" do
    subject(:error) do
      Pipeforge::ConfigurationError.new(
        message: "two errors",
        errors: [{code: :unknown_section, message: "a"}, {code: :unknown_setting, message: "b"}]
      )
    end

    it "lists the code of each entry, in order" do
      expect(error.codes).to eq(%i[unknown_section unknown_setting])
    end
  end

  describe Pipeforge::Source::MalformedSourceError do
    subject(:error) { described_class.new(message: "bad row", line: 7) }

    it "keeps the line" do
      expect(error.line).to eq(7)
    end

    it "has the code malformed_row, with the line" do
      expect(error.errors).to eq([{code: :malformed_row, message: "bad row", line: 7}])
    end
  end
end
