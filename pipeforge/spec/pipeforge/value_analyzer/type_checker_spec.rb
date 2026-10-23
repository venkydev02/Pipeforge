# frozen_string_literal: true

RSpec.describe Pipeforge::ValueAnalyzer::TypeChecker do
  subject(:type_checker) { described_class.new(type_info: type_info) }

  let(:type_info) { {type: "string"} }

  describe ".new" do
    it "raises KeyError when the type is missing" do
      expect { described_class.new(type_info: {limit: 4}) }.to raise_error(KeyError)
    end

    it "accepts the type as a symbol" do
      expect(described_class.new(type_info: {type: :integer})).to fit_text("42")
    end

    it "accepts the type as a string" do
      expect(described_class.new(type_info: {type: "integer"})).to fit_text("42")
    end
  end

  describe "#fits?" do
    context "with an integer column" do
      let(:type_info) { {type: "integer"} }

      it "fits a whole number with an optional sign" do
        expect(type_checker).to fit_text("42", "-7", "+3", "007", "0")
      end

      it "does not fit a decimal, text, a thousands separator, an exponent or a space after the sign" do
        expect(type_checker).not_to fit_text("4.5", "1,000", "twenty", "12a", "1_000", "0x1A", "1e3", "- 5")
      end

      it "holds the range of a 4-byte column by default" do
        expect(type_checker).to fit_text("2147483647", "-2147483648")
      end

      it "does not fit a number past the 4-byte range" do
        expect(type_checker).not_to fit_text("2147483648", "-2147483649")
      end

      context "with a size of 2 bytes" do
        let(:type_info) { {type: "integer", limit: 2} }

        it "holds the range of 2 bytes" do
          expect(type_checker).to fit_text("32767", "-32768")
        end

        it "does not fit a number past it" do
          expect(type_checker).not_to fit_text("32768", "-32769")
        end
      end

      context "with a size of 8 bytes" do
        let(:type_info) { {type: "integer", limit: 8} }

        it "holds the range of 8 bytes" do
          expect(type_checker).to fit_text("9223372036854775807", "-9223372036854775808")
        end

        it "does not fit a number past it" do
          expect(type_checker).not_to fit_text("9223372036854775808")
        end
      end
    end

    context "with a float column" do
      let(:type_info) { {type: "float"} }

      it "fits a number with an optional point and exponent" do
        expect(type_checker).to fit_text("4.5", "42", "-0.25", "1e3", "1.5E-3", "2e+4")
      end

      it "does not fit text, a comma, a missing digit, an incomplete exponent or a special value" do
        expect(type_checker).not_to fit_text("4,5", ".5", "5.", "abc", "1e", "0x1A", "NaN", "Infinity")
      end
    end

    context "with a decimal column" do
      let(:type_info) { {type: "decimal"} }

      it "fits a number with an optional point and no exponent" do
        expect(type_checker).to fit_text("4.5", "42", "-0.25")
      end

      it "does not fit text, a comma, a missing digit or an exponent" do
        expect(type_checker).not_to fit_text("4,5", ".5", "5.", "1e3", "abc")
      end

      context "with a precision and a scale" do
        let(:type_info) { {type: "decimal", precision: 5, scale: 2} }

        it "fits when the digits before the point fit in precision minus scale" do
          expect(type_checker).to fit_text("123.45", "-999.99", "0.5", "007.5", "12")
        end

        it "does not fit when there are too many digits before the point" do
          expect(type_checker).not_to fit_text("1234.5", "99999", "-1000")
        end

        it "allows more digits after the point than the scale, because the database only rounds them" do
          expect(type_checker).to fit_text("1.23456")
        end
      end

      context "with a precision and no scale" do
        let(:type_info) { {type: "decimal", precision: 5} }

        it "treats the scale as 0" do
          expect(type_checker).to fit_text("12345", "0.1")
        end

        it "does not fit more digits than the precision" do
          expect(type_checker).not_to fit_text("123456")
        end
      end
    end

    context "with a string column and no length limit" do
      let(:type_info) { {type: "string"} }

      it "fits any text" do
        expect(type_checker).to fit_text("anything", "42", "x" * 10_000)
      end
    end

    context "with a text column and no length limit" do
      let(:type_info) { {type: "text"} }

      it "fits any text" do
        expect(type_checker).to fit_text("x" * 10_000)
      end
    end

    context "with a text column and a length limit of 5" do
      let(:type_info) { {type: "text", max_length: 5} }

      it "fits text up to the limit, counted in characters" do
        expect(type_checker).to fit_text("12345", "héllo", "日本語日本語"[0, 5])
      end

      it "does not fit longer text" do
        expect(type_checker).not_to fit_text("123456", "日本語日本語")
      end
    end

    context "with a boolean column" do
      let(:type_info) { {type: "boolean"} }

      it "fits the fixed words, ignoring case" do
        expect(type_checker).to fit_text("true", "Yes", "n", "1", "TRUE", "f", "0", "Y", "No")
      end

      it "does not fit other words or numbers" do
        expect(type_checker).not_to fit_text("maybe", "2", "tru", "on", "-1")
      end
    end

    context "with a date column" do
      let(:type_info) { {type: "date"} }

      it "fits YYYY-MM-DD, including leap days and the ends of the calendar" do
        expect(type_checker).to fit_text("2026-10-10", "2024-02-29", "2000-02-29", "2024-12-31", "2024-01-01", "9999-12-31")
      end

      it "does not fit a day that is not in the calendar" do
        expect(type_checker).not_to fit_text(
          "2023-02-29", "1900-02-29", "2024-02-30", "2024-04-31", "2024-13-01", "2024-00-10"
        )
      end

      it "does not fit another format" do
        expect(type_checker).not_to fit_text(
          "0000-01-01", "2024-1-5", "31/01/2024", "01/31/2024", "20240131", "2024-01-31abc"
        )
      end
    end

    context "with a time column" do
      let(:type_info) { {type: "time"} }

      it "fits hh:mm with optional seconds and fraction" do
        expect(type_checker).to fit_text("10:30", "10:30:15", "23:59:59", "00:00", "10:30:15.123")
      end

      it "does not fit an hour, minute or second out of range, or another shape" do
        expect(type_checker).not_to fit_text("24:00", "10:60", "10:30:60", "9:30", "10.30", "10")
      end
    end

    context "with a timestamp column" do
      let(:type_info) { {type: "timestamp"} }

      it "fits a date and a time separated by T or one space, with an optional zone" do
        expect(type_checker).to fit_text(
          "2024-01-31 10:30:00", "2024-01-31T10:30:00Z", "2024-01-31T10:30:00+05:30",
          "2024-01-31T10:30", "2024-01-31 10:30:00.123456", "2024-01-31T10:30:00+0530"
        )
      end

      it "does not fit a date that is not in the calendar" do
        expect(type_checker).not_to fit_text("2024-02-30 10:00:00")
      end

      it "does not fit a time out of range" do
        expect(type_checker).not_to fit_text("2024-01-31 25:00:00", "2024-01-31 10:60:00", "2024-01-31 10:30:60")
      end

      it "does not fit another shape" do
        expect(type_checker).not_to fit_text("2024-01-31", "31/01/2024 10:00", "2024-01-31T10:30:00ZZ")
      end
    end

    context "with a datetime column" do
      let(:type_info) { {type: "datetime"} }

      it "follows the rule of a timestamp column" do
        expect(type_checker).to fit_text("2024-01-31 10:30:00")
      end

      it "does not fit a date that is not in the calendar" do
        expect(type_checker).not_to fit_text("2024-02-30 10:00:00")
      end
    end

    context "with a uuid column" do
      let(:type_info) { {type: "uuid"} }

      it "fits the 8-4-4-4-12 hexadecimal pattern, in either case" do
        expect(type_checker).to fit_text("123e4567-e89b-12d3-a456-426614174000", "123E4567-E89B-12D3-A456-426614174000")
      end

      it "does not fit a uuid without hyphens, in braces, or too short" do
        expect(type_checker).not_to fit_text(
          "123e4567e89b12d3a456426614174000", "{123e4567-e89b-12d3-a456-426614174000}", "123e4567", "not-a-uuid"
        )
      end
    end

    context "with a type that has no rule yet" do
      let(:type_info) { {type: "jsonb"} }

      it "fits every value" do
        expect(type_checker).to fit_text("not json", "{\"a\": 1}", "anything")
      end
    end
  end
end
