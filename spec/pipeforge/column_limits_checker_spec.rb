# frozen_string_literal: true

RSpec.describe Pipeforge::ColumnLimitsChecker do
  subject(:limits) { described_class.new(type_info: type_info) }

  describe "#violation_of" do
    subject(:violation) { limits.violation_of(value: value) }

    let(:type_info) { {type: "string"} }
    let(:value) { "x" }

    it "gives a Violation with a code and a detail" do
      limits = described_class.new(type_info: {type: "string", max_length: 1})

      expect(limits.violation_of(value: "ab")).to be_a(described_class::Violation).and have_attributes(code: :value_too_long)
    end

    context "with a type that has no limit" do
      let(:type_info) { {type: "boolean"} }
      let(:value) { true }

      it "gives nil" do
        expect(violation).to be_nil
      end
    end

    context "with a type that the core knows no limit for" do
      let(:type_info) { {type: "jsonb"} }
      let(:value) { {"a" => 1} }

      it "gives nil" do
        expect(violation).to be_nil
      end
    end

    context "with no type" do
      let(:type_info) { {} }

      it "gives nil" do
        expect(violation).to be_nil
      end
    end

    context "with a string column that has a maximum length of 3" do
      let(:type_info) { {type: "string", max_length: 3} }

      context "when the value is longer" do
        let(:value) { "abcd" }

        it "is value_too_long, saying how long it is and how long it may be" do
          expect(violation).to have_attributes(code: :value_too_long, detail: "the value has 4 characters, more than the 3 allowed")
        end
      end

      context "when the value is exactly as long" do
        let(:value) { "abc" }

        it "gives nil" do
          expect(violation).to be_nil
        end
      end

      context "when the value is not text" do
        let(:value) { 12_345 }

        it "counts the characters of its text" do
          expect(violation).to have_attributes(code: :value_too_long)
        end
      end

      context "when the value is made of multi-byte characters" do
        let(:value) { "日本語" }

        it "counts characters, not bytes" do
          expect(violation).to be_nil
        end
      end
    end

    context "with a text column that has a maximum length" do
      let(:type_info) { {type: "text", max_length: 2} }
      let(:value) { "abc" }

      it "is value_too_long" do
        expect(violation).to have_attributes(code: :value_too_long)
      end
    end

    context "with a string column that has no maximum length" do
      let(:type_info) { {type: "string", max_length: nil} }
      let(:value) { "a" * 1000 }

      it "gives nil" do
        expect(violation).to be_nil
      end
    end

    context "with an integer column of 2 bytes" do
      let(:type_info) { {type: "integer", limit: 2} }

      context "when the value is the largest that fits" do
        let(:value) { 32_767 }

        it "gives nil" do
          expect(violation).to be_nil
        end
      end

      context "when the value is the smallest that fits" do
        let(:value) { -32_768 }

        it "gives nil" do
          expect(violation).to be_nil
        end
      end

      context "when the value is one more than fits" do
        let(:value) { 32_768 }

        it "is value_out_of_range, saying how many bytes" do
          expect(violation).to have_attributes(code: :value_out_of_range, detail: "the value does not fit in 2 bytes")
        end
      end

      context "when the value is one less than fits" do
        let(:value) { -32_769 }

        it "is value_out_of_range" do
          expect(violation).to have_attributes(code: :value_out_of_range)
        end
      end
    end

    context "with an unsigned integer column of 2 bytes" do
      let(:type_info) { {type: "integer", limit: 2, unsigned: true} }

      context "when the value is above the signed range but within the unsigned one" do
        let(:value) { 65_535 }

        it "gives nil" do
          expect(violation).to be_nil
        end
      end

      context "when the value is zero" do
        let(:value) { 0 }

        it "gives nil" do
          expect(violation).to be_nil
        end
      end

      context "when the value is one more than fits" do
        let(:value) { 65_536 }

        it "is value_out_of_range" do
          expect(violation).to have_attributes(code: :value_out_of_range)
        end
      end

      context "when the value is negative" do
        let(:value) { -1 }

        it "is value_out_of_range" do
          expect(violation).to have_attributes(code: :value_out_of_range)
        end
      end
    end

    context "with an integer column that has no limit" do
      let(:type_info) { {type: "integer", limit: nil} }

      context "when the value fits 4 bytes" do
        let(:value) { 2_147_483_647 }

        it "gives nil" do
          expect(violation).to be_nil
        end
      end

      context "when the value is more than 4 bytes hold" do
        let(:value) { 2_147_483_648 }

        it "is value_out_of_range" do
          expect(violation).to have_attributes(code: :value_out_of_range, detail: "the value does not fit in 4 bytes")
        end
      end
    end

    context "with a decimal column of precision 5 and scale 2" do
      let(:type_info) { {type: "decimal", precision: 5, scale: 2} }

      context "when the number has 3 digits before the point" do
        let(:value) { BigDecimal("999.99") }

        it "gives nil" do
          expect(violation).to be_nil
        end
      end

      context "when the number has 4 digits before the point" do
        let(:value) { BigDecimal("1000.00") }

        it "is value_out_of_range, saying how many digits are allowed" do
          expect(violation).to have_attributes(
            code: :value_out_of_range, detail: "the value has more than 3 digits before the point"
          )
        end
      end

      context "when rounding to the scale adds a digit before the point" do
        let(:value) { BigDecimal("999.999") }

        it "is value_out_of_range, because the database stores 1000.00" do
          expect(violation).to have_attributes(code: :value_out_of_range)
        end
      end

      context "when rounding to the scale does not add a digit" do
        let(:value) { BigDecimal("999.994") }

        it "gives nil" do
          expect(violation).to be_nil
        end
      end

      context "when the number has more digits after the point than the scale" do
        let(:value) { BigDecimal("1.23456") }

        it "gives nil" do
          expect(violation).to be_nil
        end
      end

      context "when the number is below one" do
        let(:value) { BigDecimal("0.99") }

        it "gives nil" do
          expect(violation).to be_nil
        end
      end

      context "when the value is a Float with 4 digits before the point" do
        let(:value) { 1000.5 }

        it "is value_out_of_range" do
          expect(violation).to have_attributes(code: :value_out_of_range)
        end
      end

      context "when the value is a Float that rounds up to 4 digits" do
        let(:value) { 999.999 }

        it "is value_out_of_range" do
          expect(violation).to have_attributes(code: :value_out_of_range)
        end
      end

      context "when the value is a whole number with 4 digits" do
        let(:value) { 1000 }

        it "is value_out_of_range" do
          expect(violation).to have_attributes(code: :value_out_of_range)
        end
      end

      context "when the value is a negative number with 4 digits" do
        let(:value) { -1000.5 }

        it "does not count the sign" do
          expect(violation).to have_attributes(code: :value_out_of_range)
        end
      end

      context "when the value is not finite" do
        let(:value) { Float::NAN }

        it "gives nil, leaving it to the cast" do
          expect(violation).to be_nil
        end
      end
    end

    context "with a decimal column that has a precision and no scale" do
      let(:type_info) { {type: "decimal", precision: 3, scale: nil} }

      context "when the number has more digits before the point than the precision" do
        let(:value) { 1234 }

        it "is value_out_of_range" do
          expect(violation).to have_attributes(code: :value_out_of_range)
        end
      end

      context "when rounding to a whole number adds a digit" do
        let(:value) { BigDecimal("999.5") }

        it "is value_out_of_range" do
          expect(violation).to have_attributes(code: :value_out_of_range)
        end
      end
    end

    context "with a decimal column that has no precision" do
      let(:type_info) { {type: "decimal", precision: nil} }
      let(:value) { BigDecimal(123_456_789_012_345_678_901_234_567_890) }

      it "gives nil" do
        expect(violation).to be_nil
      end
    end

    context "with a float column of double precision" do
      let(:type_info) { {type: "float"} }

      context "when the value is a number the column holds" do
        let(:value) { 1.5e300 }

        it "gives nil" do
          expect(violation).to be_nil
        end
      end

      context "when the value has been cast to infinity" do
        let(:value) { Float::INFINITY }

        it "is value_out_of_range" do
          expect(violation).to have_attributes(
            code: :value_out_of_range, detail: "the value is larger than a float of this column can hold"
          )
        end
      end

      context "when the value is negative infinity" do
        let(:value) { -Float::INFINITY }

        it "is value_out_of_range" do
          expect(violation).to have_attributes(code: :value_out_of_range)
        end
      end

      context "when the value is a whole number" do
        let(:value) { 42 }

        it "gives nil" do
          expect(violation).to be_nil
        end
      end

      context "when the value is not a number" do
        let(:value) { Float::NAN }

        it "gives nil, leaving it to the cast" do
          expect(violation).to be_nil
        end
      end
    end

    context "with a float column of single precision" do
      let(:type_info) { {type: "float", limit: 24} }

      context "when the value is within the single precision range" do
        let(:value) { 3.4e38 }

        it "gives nil" do
          expect(violation).to be_nil
        end
      end

      context "when the value is past it, though a double precision float holds it" do
        let(:value) { -3.5e38 }

        it "is value_out_of_range" do
          expect(violation).to have_attributes(code: :value_out_of_range)
        end
      end
    end

    context "with an enum column stored as a number" do
      let(:type_info) { {type: "integer", enum_values: {"draft" => 0, "placed" => 1}} }

      context "when the value is a label" do
        let(:value) { "draft" }

        it "gives nil" do
          expect(violation).to be_nil
        end
      end

      context "when the value is a stored value written as text" do
        let(:value) { "1" }

        it "gives nil" do
          expect(violation).to be_nil
        end
      end

      context "when the value is a stored value that is a number" do
        let(:value) { 1 }

        it "gives nil" do
          expect(violation).to be_nil
        end
      end

      context "when the value is neither" do
        let(:value) { "shipped" }

        it "is value_not_allowed, listing the labels and not quoting the value" do
          expect(violation).to have_attributes(code: :value_not_allowed, detail: "the value is not one of draft, placed")
        end
      end

      it "does not apply the integer range to an enum column" do
        limits = described_class.new(type_info: {type: "integer", limit: 1, enum_values: {"big" => 100_000}})

        expect(limits.violation_of(value: "100000")).to be_nil
      end
    end

    context "with an enum column stored as text" do
      let(:type_info) { {type: "string", enum_values: {"retail" => "r", "wholesale" => "w"}} }

      context "when the value is a stored value" do
        let(:value) { "w" }

        it "gives nil" do
          expect(violation).to be_nil
        end
      end

      context "when the value is not a label or a stored value" do
        let(:value) { "x" }

        it "is value_not_allowed" do
          expect(violation).to have_attributes(code: :value_not_allowed)
        end
      end
    end

    context "with enum_values that are nil" do
      let(:type_info) { {type: "string", enum_values: nil} }
      let(:value) { "anything" }

      it "is not an enum column" do
        expect(violation).to be_nil
      end
    end
  end
end
