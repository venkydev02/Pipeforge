# frozen_string_literal: true

RSpec.describe "the errors the engine raises on purpose" do
  [
    Pipeforge::ConfigurationError,
    Pipeforge::Source::MissingSourceError,
    Pipeforge::Source::EmptySourceError,
    Pipeforge::Source::MissingColumnError,
    Pipeforge::Source::MalformedSourceError
  ].each do |error_class|
    it "#{error_class} is a Pipeforge::Error" do
      expect(error_class.ancestors).to include(Pipeforge::Error)
    end
  end

  it "keeps the line on a malformed source error" do
    error = Pipeforge::Source::MalformedSourceError.new(message: "bad row", line: 7)

    expect(error.message).to eq("bad row")
    expect(error.line).to eq(7)
  end
end
