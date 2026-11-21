# frozen_string_literal: true

# Each describe is one part of the checker, named as the code names it. Each context gives the limits
# of the column and the value that is checked, with the field names and values as the code spells them,
# and each example says what the checker does to the value: it accepts it, or refuses it with the error that the
# ErrorCatalog builds for the mistake (the checker promises that error, so it is compared with the catalog's own call
# and no sentence is copied here). The whole error is compared in the first refusing example of each kind and the
# code only after that.
# An accepting example that no break fails alone is kept for what it says the rule accepts (contract only).
# Utilities.largest_float is a pure helper and stays real.
RSpec.describe Pipeforge::ColumnLimitsChecker do
  subject(:checker) { described_class.new(target_column_name: "amount", type: type, **limits) }

  let(:answer) { checker.violation_of(value: value) }

  def catalog_error(key, **facts)
    Pipeforge::ErrorCatalog::ERRORS.fetch(key).call(
      origin: :schema, target_column_name: "amount", value: value.as_json, **facts
    )
  end

  # The factory only creates the checker with the values of the target column; what the checker does with
  # them is the examples of #violation_of.
  describe ".for" do
    let(:target_column) do
      build_target_column(
        name: "amount", type: "decimal", limit: 4, is_signed: false, max_length: 3, precision: 7, scale: 2,
        enum_labels: %w[draft placed]
      )
    end

    before { allow(described_class).to receive(:new).and_call_original }

    context "when the target column has a name, type, limit, is_signed, max_length, precision, scale and enum_labels" do
      it "creates the checker with each of them" do
        described_class.for(target_column: target_column)

        expect(described_class).to have_received(:new).with(
          target_column_name: "amount", type: "decimal", limit: 4, is_signed: false, max_length: 3, precision: 7,
          scale: 2, enum_labels: %w[draft placed]
        )
      end
    end
  end

  describe "#violation_of" do
    # The enum is checked before the type: an integer column with labels is not held to the integer range.
    describe "enum_labels" do
      let(:type) { "integer" }

      context "when enum_labels is %w[draft placed]" do
        let(:limits) { {enum_labels: %w[draft placed]} }

        context "and the value is \"draft\"" do
          let(:value) { "draft" }

          it "accepts it" do
            expect(answer).to be_nil
          end
        end

        context "and the value is \"shipped\"" do
          let(:value) { "shipped" }

          it "refuses it with value_not_allowed, naming the labels and not the value" do
            expect(answer).to eq(catalog_error(:value_not_allowed, labels: %w[draft placed]))
          end
        end

        # A value mapping can give a Symbol; its text is compared with the labels.
        context "and the value is :placed" do
          let(:value) { :placed }

          it "accepts it" do
            expect(answer).to be_nil
          end
        end

        context "and the value is \"Draft\"" do
          let(:value) { "Draft" }

          it "refuses it with value_not_allowed, because a label is matched as it is written" do
            expect(answer.code).to eq(:value_not_allowed)
          end
        end
      end
    end

    describe 'type "string"' do
      let(:type) { "string" }

      context "when max_length is 3" do
        let(:limits) { {max_length: 3} }

        context "and the value is \"abcd\"" do
          let(:value) { "abcd" }

          it "refuses it with value_too_long, naming the length found and max_length" do
            expect(answer).to eq(catalog_error(:value_too_long, length: 4, max_length: 3))
          end
        end

        context "and the value is 12_345, which is not text" do
          let(:value) { 12_345 }

          it "refuses it with value_too_long, because the text of the value is counted" do
            expect(answer.code).to eq(:value_too_long)
          end
        end

        context "and the value is \"日本語\"" do
          let(:value) { "日本語" }

          it "accepts it, because characters are counted and not bytes (3 characters, 9 bytes)" do
            expect(answer).to be_nil
          end
        end
      end

      context "when max_length is nil" do
        let(:limits) { {max_length: nil} }

        context "and the value has 10_000 characters" do
          let(:value) { "a" * 10_000 }

          it "accepts it" do
            expect(answer).to be_nil
          end
        end
      end
    end

    describe 'type "text"' do
      let(:type) { "text" }

      context "when max_length is 3" do
        let(:limits) { {max_length: 3} }

        context "and the value is \"abcd\"" do
          let(:value) { "abcd" }

          it "refuses it with value_too_long" do
            expect(answer.code).to eq(:value_too_long)
          end
        end
      end
    end

    describe 'type "integer"' do
      let(:type) { "integer" }

      context "when limit is 2 and is_signed is true" do
        let(:limits) { {limit: 2, is_signed: true} }

        context "and the value is -32_768" do
          let(:value) { -32_768 }

          it "accepts it" do
            expect(answer).to be_nil
          end
        end

        context "and the value is 32_768" do
          let(:value) { 32_768 }

          it "refuses it with value_out_of_range, naming limit as the bytes" do
            expect(answer).to eq(catalog_error(:value_out_of_range_bytes, bytes: 2))
          end
        end
      end

      context "when limit is 2 and is_signed is false" do
        let(:limits) { {limit: 2, is_signed: false} }

        context "and the value is 65_535" do
          let(:value) { 65_535 }

          it "accepts it" do
            expect(answer).to be_nil
          end
        end

        context "and the value is 65_536" do
          let(:value) { 65_536 }

          it "refuses it with value_out_of_range" do
            expect(answer.code).to eq(:value_out_of_range)
          end
        end

        context "and the value is -1" do
          let(:value) { -1 }

          it "refuses it with value_out_of_range" do
            expect(answer.code).to eq(:value_out_of_range)
          end
        end
      end

      context "when limit is nil" do
        let(:limits) { {limit: nil} }

        context "and the value is 2_147_483_647" do
          let(:value) { 2_147_483_647 }

          it "accepts it" do
            expect(answer).to be_nil
          end
        end

        context "and the value is 2_147_483_648" do
          let(:value) { 2_147_483_648 }

          it "refuses it with value_out_of_range, reading limit as 4 bytes" do
            expect(answer.code).to eq(:value_out_of_range)
          end
        end
      end
    end

    describe 'type "decimal"' do
      let(:type) { "decimal" }

      context "when precision is 5 and scale is 2" do
        let(:limits) { {precision: 5, scale: 2} }

        context "and the value is BigDecimal(\"999.99\")" do
          let(:value) { BigDecimal("999.99") }

          it "accepts it" do
            expect(answer).to be_nil
          end
        end

        context "and the value is BigDecimal(1000)" do
          let(:value) { BigDecimal(1000) }

          it "refuses it with value_out_of_range, naming the 3 digits before the point that precision minus scale allows" do
            expect(answer).to eq(catalog_error(:value_out_of_range_digits, allowed_digits: 3))
          end
        end

        context "and the value is BigDecimal(\"999.999\")" do
          let(:value) { BigDecimal("999.999") }

          # The database stores it rounded to scale 2, as 1000.00.
          it "refuses it with value_out_of_range" do
            expect(answer.code).to eq(:value_out_of_range)
          end
        end

        context "and the value is BigDecimal(\"999.9949999999999999999\")" do
          let(:value) { BigDecimal("999.9949999999999999999") }

          # A Float would read it as 999.995, which rounds up to 1000.00; only an exact rounding gives 999.99.
          it "accepts it" do
            expect(answer).to be_nil
          end
        end

        context "and the value is BigDecimal(\"-999.99\")" do
          let(:value) { BigDecimal("-999.99") }

          it "accepts it, because the sign is not a digit" do
            expect(answer).to be_nil
          end
        end

        context "and the value is BigDecimal(\"Infinity\")" do
          let(:value) { BigDecimal("Infinity") }

          it "accepts it, because a value that is not finite is left to the cast" do
            expect(answer).to be_nil
          end
        end
      end

      context "when precision is 5 and scale is nil" do
        let(:limits) { {precision: 5, scale: nil} }

        context "and the value is 99_999" do
          let(:value) { 99_999 }

          it "accepts it, reading scale as 0, so all 5 digits are before the point" do
            expect(answer).to be_nil
          end
        end
      end

      context "when precision is 2 and scale is 2" do
        let(:limits) { {precision: 2, scale: 2} }

        context "and the value is BigDecimal(\"0.5\")" do
          let(:value) { BigDecimal("0.5") }

          # The zero in front of the point is not a digit.
          it "accepts it" do
            expect(answer).to be_nil
          end
        end
      end

      context "when precision is nil" do
        let(:limits) { {precision: nil} }

        context "and the value has 60 digits" do
          let(:value) { BigDecimal("1" * 60) }

          it "accepts it" do
            expect(answer).to be_nil
          end
        end
      end
    end

    describe 'type "float"' do
      let(:type) { "float" }

      context "when limit is nil" do
        let(:limits) { {limit: nil} }

        context "and the value is Float::MAX" do
          let(:value) { Float::MAX }

          it "accepts it" do
            expect(answer).to be_nil
          end
        end

        context "and the value is Float::INFINITY" do
          let(:value) { Float::INFINITY }

          it "refuses it with value_out_of_range" do
            expect(answer).to eq(catalog_error(:value_out_of_range_float))
          end
        end

        context "and the value is Float::NAN" do
          let(:value) { Float::NAN }

          it "accepts it, because a value that is not a number is left to the cast" do
            expect(answer).to be_nil
          end
        end
      end

      context "when limit is 24" do
        let(:limits) { {limit: 24} }

        context "and the value is 3.4e38" do
          let(:value) { 3.4e38 }

          it "accepts it" do
            expect(answer).to be_nil
          end
        end

        context "and the value is -3.5e38" do
          let(:value) { -3.5e38 }

          it "refuses it with value_out_of_range, on the negative side as on the positive" do
            expect(answer.code).to eq(:value_out_of_range)
          end
        end
      end
    end

    describe "a type with no limit" do
      context "when type is \"boolean\"" do
        let(:type) { "boolean" }
        let(:limits) { {} }
        let(:value) { true }

        it "accepts any value" do
          expect(answer).to be_nil
        end
      end

      context "when type is nil" do
        let(:type) { nil }
        let(:limits) { {} }
        let(:value) { "a" * 10_000 }

        it "accepts any value" do
          expect(answer).to be_nil
        end
      end
    end

    describe "a Symbol type" do
      context "when type is :string and max_length is 1" do
        let(:type) { :string }
        let(:limits) { {max_length: 1} }

        context "and the value is \"ab\"" do
          let(:value) { "ab" }

          it "refuses it with value_too_long, reading the type as the text \"string\"" do
            expect(answer.code).to eq(:value_too_long)
          end
        end
      end
    end
  end
end
