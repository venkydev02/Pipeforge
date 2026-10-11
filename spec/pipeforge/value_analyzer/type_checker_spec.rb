# frozen_string_literal: true

RSpec.describe Pipeforge::ValueAnalyzer::TypeChecker do
  subject(:checker) { described_class.new(type_info: type_info) }

  # Each value becomes one example, so a failure names the value.
  shared_examples "values that fit" do |*texts|
    texts.each do |text|
      it "fits #{text.inspect}" do
        expect(checker.fits?(text: text)).to be true
      end
    end
  end

  shared_examples "values that do not fit" do |*texts|
    texts.each do |text|
      it "does not fit #{text.inspect}" do
        expect(checker.fits?(text: text)).to be false
      end
    end
  end

  describe ".new" do
    it "raises KeyError when the type is missing" do
      expect { described_class.new(type_info: {limit: 4}) }.to raise_error(KeyError)
    end

    it "accepts the type as a symbol" do
      expect(described_class.new(type_info: {type: :integer}).fits?(text: "42")).to be true
    end
  end

  describe "#fits?" do
    context "with an integer column" do
      let(:type_info) { {type: "integer"} }

      include_examples "values that fit", "42", "-7", "+3", "007", "0"
      include_examples "values that do not fit", "4.5", "1,000", "twenty", "12a", "1_000", "0x1A", "1e3", "- 5"

      context "with the default size of 4 bytes" do
        include_examples "values that fit", "2147483647", "-2147483648"
        include_examples "values that do not fit", "2147483648", "-2147483649"
      end

      context "with a size of 2 bytes" do
        let(:type_info) { {type: "integer", limit: 2} }

        include_examples "values that fit", "32767", "-32768"
        include_examples "values that do not fit", "32768", "-32769"
      end

      context "with a size of 8 bytes" do
        let(:type_info) { {type: "integer", limit: 8} }

        include_examples "values that fit", "9223372036854775807", "-9223372036854775808"
        include_examples "values that do not fit", "9223372036854775808"
      end
    end

    context "with a float column" do
      let(:type_info) { {type: "float"} }

      include_examples "values that fit", "4.5", "42", "-0.25", "1e3", "1.5E-3", "2e+4"
      include_examples "values that do not fit", "4,5", ".5", "5.", "abc", "1e", "0x1A", "NaN", "Infinity"
    end

    context "with a decimal column" do
      let(:type_info) { {type: "decimal"} }

      include_examples "values that fit", "4.5", "42", "-0.25"
      include_examples "values that do not fit", "4,5", ".5", "5.", "1e3", "abc"

      context "with a precision and a scale" do
        let(:type_info) { {type: "decimal", precision: 5, scale: 2} }

        include_examples "values that fit", "123.45", "-999.99", "0.5", "007.5", "12"
        include_examples "values that do not fit", "1234.5", "99999", "-1000"

        it "allows more digits after the point than the scale, because the database only rounds them" do
          expect(checker.fits?(text: "1.23456")).to be true
        end
      end

      context "with a precision and no scale" do
        let(:type_info) { {type: "decimal", precision: 5} }

        include_examples "values that fit", "12345", "0.1"
        include_examples "values that do not fit", "123456"
      end
    end

    context "with a string or text column" do
      let(:type_info) { {type: "string"} }

      context "without a length limit" do
        include_examples "values that fit", "anything", "42", "x" * 10_000
      end

      context "with a length limit" do
        let(:type_info) { {type: "text", max_length: 5} }

        include_examples "values that fit", "12345", "héllo", "日本語日本語"[0, 5]
        include_examples "values that do not fit", "123456", "日本語日本語"
      end
    end

    context "with a boolean column" do
      let(:type_info) { {type: "boolean"} }

      include_examples "values that fit", "true", "Yes", "n", "1", "TRUE", "f", "0", "Y", "No"
      include_examples "values that do not fit", "maybe", "2", "tru", "on", "-1"
    end

    context "with a date column" do
      let(:type_info) { {type: "date"} }

      include_examples "values that fit", "2026-10-10", "2024-02-29", "2000-02-29", "2024-12-31", "2024-01-01", "9999-12-31"
      include_examples "values that do not fit",
        "2023-02-29", "1900-02-29", "2024-02-30", "2024-04-31", "2024-13-01", "2024-00-10",
        "0000-01-01", "2024-1-5", "31/01/2024", "01/31/2024", "20240131", "2024-01-31abc"
    end

    context "with a time column" do
      let(:type_info) { {type: "time"} }

      include_examples "values that fit", "10:30", "10:30:15", "23:59:59", "00:00", "10:30:15.123"
      include_examples "values that do not fit", "24:00", "10:60", "10:30:60", "9:30", "10.30", "10"
    end

    %w[timestamp datetime].each do |type|
      context "with a #{type} column" do
        let(:type_info) { {type: type} }

        include_examples "values that fit",
          "2024-01-31 10:30:00", "2024-01-31T10:30:00Z", "2024-01-31T10:30:00+05:30",
          "2024-01-31T10:30", "2024-01-31 10:30:00.123456", "2024-01-31T10:30:00+0530"
        include_examples "values that do not fit",
          "2024-02-30 10:00:00", "2024-01-31 25:00:00", "2024-01-31 10:60:00", "2024-01-31 10:30:60",
          "2024-01-31", "31/01/2024 10:00", "2024-01-31T10:30:00ZZ"
      end
    end

    context "with a uuid column" do
      let(:type_info) { {type: "uuid"} }

      include_examples "values that fit", "123e4567-e89b-12d3-a456-426614174000", "123E4567-E89B-12D3-A456-426614174000"
      include_examples "values that do not fit",
        "123e4567e89b12d3a456426614174000", "{123e4567-e89b-12d3-a456-426614174000}", "123e4567", "not-a-uuid"
    end

    context "with a type that has no rule yet" do
      let(:type_info) { {type: "jsonb"} }

      include_examples "values that fit", "not json", "{\"a\": 1}", "anything"
    end
  end
end
