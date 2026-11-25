# frozen_string_literal: true

# Each mapped column has a source column name that differs from its target column name, so a value read under the
# wrong name shows.
RSpec.describe Pipeforge::RunProcessor::SchemaChecker do
  def resolve(*target_columns)
    mapped_columns = {}

    target_columns.each do |target_column|
      mapped_columns[target_column.name] = {source_column_name: "source #{target_column.name}"}
    end

    resolve_mapped_columns_of(target_columns: target_columns, mapped_columns: mapped_columns)
  end

  def script_limits(target_column:, answer: nil)
    limits = instance_double(Pipeforge::ColumnLimitsChecker)
    allow(limits).to receive(:violation_of).and_return(answer)
    allow(Pipeforge::ColumnLimitsChecker).to receive(:for).with(target_column: target_column).and_return(limits)
    limits
  end

  def missing_error(target_column_name:)
    Pipeforge::ErrorCatalog::ERRORS.fetch(:value_missing).call(
      origin: :schema, target_column_name: target_column_name, value: nil
    )
  end

  def too_long_error(target_column_name:, value:)
    Pipeforge::ErrorCatalog::ERRORS.fetch(:value_too_long).call(
      origin: :schema, target_column_name: target_column_name, value: value, length: value.length, max_length: 3
    )
  end

  describe ".new" do
    let(:email_column) { build_target_column(name: "email") }
    let(:name_column) { build_target_column(name: "name") }

    context "when resolved_mapped_columns is a Hash of target column name => mapped column" do
      subject(:checker) { described_class.new(resolved_mapped_columns: resolve(email_column)) }

      before { script_limits(target_column: email_column) }

      it "gives a checker that answers call" do
        expect(checker).to respond_to(:call)
      end
    end

    context "when resolved_mapped_columns is empty" do
      subject(:checker) { described_class.new(resolved_mapped_columns: {}) }

      it "gives no error for any attributes" do
        expect(checker.call(attributes: {"email" => nil, "name" => "x"})).to eq([])
      end
    end

    context "when resolved_mapped_columns has the columns email and name" do
      let(:resolved_mapped_columns_of_email_and_name) { resolve(email_column, name_column) }

      before do
        script_limits(target_column: email_column)
        script_limits(target_column: name_column)
        described_class.new(resolved_mapped_columns: resolved_mapped_columns_of_email_and_name)
      end

      it "asks ColumnLimitsChecker.for with the target column of email" do
        expect(Pipeforge::ColumnLimitsChecker).to have_received(:for).with(target_column: email_column)
      end

      it "asks ColumnLimitsChecker.for with the target column of name" do
        expect(Pipeforge::ColumnLimitsChecker).to have_received(:for).with(target_column: name_column)
      end
    end
  end

  describe "#call" do
    subject(:errors) { checker.call(attributes: attributes) }

    context "when attributes is a Hash of target column name => value that passes every check" do
      let(:name_column) { build_target_column(name: "name") }
      let(:checker) { described_class.new(resolved_mapped_columns: resolve(name_column)) }
      let(:attributes_that_pass) { {"name" => "Ada"} }
      let(:attributes) { attributes_that_pass }

      before { script_limits(target_column: name_column) }

      it "gives an empty Array of errors" do
        expect(errors).to eq([])
      end
    end

    describe "a required column" do
      context "when required is true" do
        let(:required_email_column) { build_target_column(name: "email", required: true) }
        let(:checker) { described_class.new(resolved_mapped_columns: resolve(required_email_column)) }

        before { script_limits(target_column: required_email_column) }

        context "and the value is nil" do
          let(:attributes_with_empty_email) { {"email" => nil} }
          let(:attributes) { attributes_with_empty_email }

          it "refuses it with value_missing, as the ErrorCatalog builds it with origin schema" do
            expect(errors).to eq([missing_error(target_column_name: "email")])
          end
        end

        context "and the column is left out of the attributes" do
          let(:attributes_without_email) { {} }
          let(:attributes) { attributes_without_email }

          it "refuses it with value_missing" do
            expect(errors).to eq([missing_error(target_column_name: "email")])
          end
        end

        context "and the value is false" do
          let(:attributes_with_false_email) { {"email" => false} }
          let(:attributes) { attributes_with_false_email }

          it "accepts it" do
            expect(errors).to eq([])
          end
        end
      end
    end

    describe "a column that is not required" do
      context "when required is false" do
        let(:optional_email_column) { build_target_column(name: "email", required: false) }
        let(:checker) { described_class.new(resolved_mapped_columns: resolve(optional_email_column)) }

        before { script_limits(target_column: optional_email_column) }

        context "and the value is nil" do
          let(:attributes_with_empty_email) { {"email" => nil} }
          let(:attributes) { attributes_with_empty_email }

          it "accepts it" do
            expect(errors).to eq([])
          end
        end
      end
    end

    describe "a column that has a value" do
      let(:email_column) { build_target_column(name: "email") }
      let(:checker) { described_class.new(resolved_mapped_columns: resolve(email_column)) }
      let(:attributes_with_email) { {"email" => "ada@example.com"} }
      let(:attributes) { attributes_with_email }

      context "when the limits checker answers nil for the value" do
        let!(:limits_without_a_violation) { script_limits(target_column: email_column, answer: nil) }

        it "accepts it" do
          expect(errors).to eq([])
        end
      end

      context "when the limits checker answers an error for the value" do
        let(:violation) { too_long_error(target_column_name: "email", value: "ada@example.com") }
        let!(:limits_with_a_violation) { script_limits(target_column: email_column, answer: violation) }

        it "gives that error, as it is" do
          expect(errors.first).to equal(violation)
        end

        it "gives no other error" do
          expect(errors).to eq([violation])
        end
      end
    end

    describe "columns and keys the checker was not built for" do
      let(:name_column) { build_target_column(name: "name") }
      let(:checker) { described_class.new(resolved_mapped_columns: resolve(name_column)) }
      let!(:name_limits) { script_limits(target_column: name_column) }

      context "when a required column is filled by no mapped column and has no value" do
        let(:attributes_with_empty_unmapped_email) { {"name" => "Ada", "email" => nil} }
        let(:attributes) { attributes_with_empty_unmapped_email }

        it "gives no error for it" do
          expect(errors).to eq([])
        end
      end

      context "when the attributes hold the key nickname, which is not a mapped column" do
        let(:attributes_with_unmapped_nickname) { {"name" => "Ada", "nickname" => "toolong"} }
        let(:attributes) { attributes_with_unmapped_nickname }

        it "gives no error for it" do
          expect(errors).to eq([])
        end

        it "asks no limits for its value" do
          errors

          expect(name_limits).not_to have_received(:violation_of).with(value: "toolong")
        end
      end
    end

    describe "several columns" do
      context "when email is required, and name and age each have a violation" do
        let(:required_email_column) { build_target_column(name: "email", required: true) }
        let(:name_column) { build_target_column(name: "name") }
        let(:age_column) { build_target_column(name: "age") }
        let(:name_violation) { too_long_error(target_column_name: "name", value: "Ada Lovelace") }
        let(:age_violation) { too_long_error(target_column_name: "age", value: "forty-two") }
        let(:checker) do
          described_class.new(resolved_mapped_columns: resolve(required_email_column, name_column, age_column))
        end

        before do
          script_limits(target_column: required_email_column)
          script_limits(target_column: name_column, answer: name_violation)
          script_limits(target_column: age_column, answer: age_violation)
        end

        context "and the attributes are listed as age, name, email" do
          let(:attributes_listed_as_age_name_email) do
            {"age" => "forty-two", "name" => "Ada Lovelace", "email" => nil}
          end
          let(:attributes) { attributes_listed_as_age_name_email }

          it "gives one error for each, in the order of the mapped columns" do
            expect(errors).to eq([missing_error(target_column_name: "email"), name_violation, age_violation])
          end
        end
      end
    end

    context "when email is required and its value is nil" do
      let(:required_email_column) { build_target_column(name: "email", required: true) }
      let(:violation) { too_long_error(target_column_name: "email", value: "") }
      let!(:limits_with_a_violation) { script_limits(target_column: required_email_column, answer: violation) }
      let(:checker) { described_class.new(resolved_mapped_columns: resolve(required_email_column)) }
      let(:attributes_with_empty_email) { {"email" => nil} }
      let(:attributes) { attributes_with_empty_email }

      it "does not ask the limits checker for it" do
        errors

        expect(limits_with_a_violation).not_to have_received(:violation_of)
      end

      it "gives value_missing as its one error" do
        expect(errors).to eq([missing_error(target_column_name: "email")])
      end
    end

    context "when email is not required and its value is nil" do
      let(:optional_email_column) { build_target_column(name: "email", required: false) }
      let(:violation) { too_long_error(target_column_name: "email", value: "") }
      let!(:limits_with_a_violation) { script_limits(target_column: optional_email_column, answer: violation) }
      let(:checker) { described_class.new(resolved_mapped_columns: resolve(optional_email_column)) }
      let(:attributes_with_empty_email) { {"email" => nil} }
      let(:attributes) { attributes_with_empty_email }

      it "does not ask the limits checker for it" do
        errors

        expect(limits_with_a_violation).not_to have_received(:violation_of)
      end
    end

    context "when the same checker is called with attributes that give an error and then with ones that pass" do
      let(:code_column) { build_target_column(name: "code") }
      let(:violation) { too_long_error(target_column_name: "code", value: "abcd") }
      let(:checker) { described_class.new(resolved_mapped_columns: resolve(code_column)) }
      let(:attributes_with_a_violation) { {"code" => "abcd"} }
      let(:attributes_that_pass) { {"code" => "abc"} }
      let(:attributes) { attributes_that_pass }

      before do
        limits = script_limits(target_column: code_column, answer: violation)
        allow(limits).to receive(:violation_of).with(value: "abc").and_return(nil)
        checker.call(attributes: attributes_with_a_violation)
      end

      it "gives no error for the second call" do
        expect(errors).to eq([])
      end
    end

    describe "the answers of the limits checker" do
      context "when two mapped columns have limits checkers scripted with different answers" do
        let(:email_column) { build_target_column(name: "email") }
        let(:name_column) { build_target_column(name: "name") }
        let(:email_violation) { too_long_error(target_column_name: "email", value: "ada@example.com") }
        let(:name_violation) { too_long_error(target_column_name: "name", value: "Ada Lovelace") }
        let(:checker) { described_class.new(resolved_mapped_columns: resolve(email_column, name_column)) }
        let(:attributes_with_email_and_name) { {"email" => "ada@example.com", "name" => "Ada Lovelace"} }
        let(:attributes) { attributes_with_email_and_name }

        before do
          script_limits(target_column: email_column, answer: email_violation)
          script_limits(target_column: name_column, answer: name_violation)
        end

        it "keeps the answer of each for its own column" do
          expect(errors).to eq([email_violation, name_violation])
        end
      end
    end

    describe "collaboration with the real ColumnLimitsChecker" do
      context "when the mapped column code has a source column name that differs and the value is \"abcd\"" do
        let(:string_column_of_3_characters) { build_target_column(name: "code", type: "string", max_length: 3) }
        let(:real_limits) { Pipeforge::ColumnLimitsChecker.for(target_column: string_column_of_3_characters) }
        let(:checker) { described_class.new(resolved_mapped_columns: resolve(string_column_of_3_characters)) }
        let(:attributes_with_the_value_under_both_names) { {"code" => "abcd", "source code" => "other"} }
        let(:attributes) { attributes_with_the_value_under_both_names }

        before do
          allow(Pipeforge::ColumnLimitsChecker).to receive(:for)
            .with(target_column: string_column_of_3_characters).and_return(real_limits)
          allow(real_limits).to receive(:violation_of).and_call_original
        end

        it "asks the real limits checker with exactly the value under code, and gives its real answer" do
          expect(errors).to eq([too_long_error(target_column_name: "code", value: "abcd")])
          expect(real_limits).to have_received(:violation_of).with(value: "abcd")
        end
      end

      context "when the real limits checker is used for a string column with max_length 3" do
        let(:code_column) { build_target_column(name: "code", type: "string", max_length: 3) }
        let(:checker) { described_class.new(resolved_mapped_columns: resolve(code_column)) }

        context "and the value is \"abcd\"" do
          let(:attributes_with_long_code) { {"code" => "abcd"} }
          let(:attributes) { attributes_with_long_code }

          it "gives the value_too_long error the ErrorCatalog builds, with origin schema and the value that failed" do
            expect(errors).to eq([too_long_error(target_column_name: "code", value: "abcd")])
          end
        end
      end
    end
  end
end
