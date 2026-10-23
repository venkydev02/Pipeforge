# frozen_string_literal: true

RSpec.describe Pipeforge::Error do
  describe "the errors the engine raises on purpose" do
    it "includes ConfigurationError" do
      expect(Pipeforge::ConfigurationError.ancestors).to include(described_class)
    end

    it "includes InvalidMappedColumnsError" do
      expect(Pipeforge::InvalidMappedColumnsError.ancestors).to include(described_class)
    end

    it "includes Source::UnsupportedSourceError" do
      expect(Pipeforge::Source::UnsupportedSourceError.ancestors).to include(described_class)
    end

    it "includes Source::EmptySourceError" do
      expect(Pipeforge::Source::EmptySourceError.ancestors).to include(described_class)
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
        errors: [{code: :unknown_section, message: "a"}, {code: :unknown_setting, message: "b"}]
      )
    end

    it "lists the code of each entry, in order" do
      expect(error.codes).to eq(%i[unknown_section unknown_setting])
    end
  end

  describe "#message" do
    let(:entries) { [{code: :unknown_section, message: "first mistake"}, {code: :unknown_setting, message: "second mistake"}] }

    it "joins the messages of the entries when no message is given" do
      error = Pipeforge::ConfigurationError.new(errors: entries)

      expect(error.message).to eq("first mistake; second mistake")
    end

    it "is the message of the entry when there is one entry" do
      error = Pipeforge::ConfigurationError.new(errors: [entries.first])

      expect(error.message).to eq("first mistake")
    end

    it "is the given message when one is given" do
      error = Pipeforge::ConfigurationError.new(errors: entries, message: "its own layout")

      expect(error.message).to eq("its own layout")
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
