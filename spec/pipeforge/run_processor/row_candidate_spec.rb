# frozen_string_literal: true

RSpec.describe Pipeforge::RunProcessor::RowCandidate do
  subject(:candidate) do
    described_class.new(
      row_number: 7, mapped_values: mapped_values, record_attributes: record_attributes, model_adapter: model_adapter
    )
  end

  let(:target_columns) do
    [
      build_target_column(name: "email", required: true),
      build_target_column(name: "status", default: "open"),
      build_target_column(name: "note")
    ]
  end
  let(:target_schema) { build_target_schema(columns: target_columns) }
  let(:mapped_values) { {"email" => "ann@example.com", "status" => "closed", "note" => nil} }
  let(:record_attributes) { mapped_values }
  let(:model_adapter) { FakeModelAdapter.new(errors_of: errors_of) }
  let(:errors_of) { ->(attributes:) { [] } }
  let(:schema_checker) { Pipeforge::RunProcessor::SchemaChecker.new(target_schema: target_schema) }

  def model_error(code:, target_column:, message: "from the model")
    {origin: :model, code: code, message: message, target_column: target_column}
  end

  describe ".new" do
    it "keeps the row number and the mapped values" do
      expect(candidate).to have_attributes(row_number: 7, mapped_values: mapped_values)
    end

    it "starts with no errors" do
      expect(candidate.errors).to eq([])
    end

    it "keeps the record attributes it is given apart from the mapped values" do
      given_record_attributes = {"email" => "ann@example.com", "note" => nil}
      candidate = described_class.new(
        row_number: 7, mapped_values: mapped_values, record_attributes: given_record_attributes,
        model_adapter: model_adapter
      )

      expect(candidate).to have_attributes(mapped_values: mapped_values, record_attributes: given_record_attributes)
    end

    it "gives the model adapter the record attributes to build the record from" do
      candidate

      expect(model_adapter.built_attributes).to eq([{"email" => "ann@example.com", "status" => "closed", "note" => nil}])
    end

    it "keeps the record the model adapter built" do
      expect(candidate.model_record.attributes).to eq(candidate.record_attributes)
    end
  end

  describe "#valid?" do
    context "when neither level finds a mistake" do
      it "is true, with no errors" do
        expect(candidate.valid?(schema_checker: schema_checker)).to be(true)
        expect(candidate.errors).to eq([])
      end
    end

    context "when the model finds a mistake" do
      let(:errors_of) { ->(attributes:) { [model_error(code: :value_not_unique, target_column: "email")] } }

      it "is false, with that error" do
        expect(candidate.valid?(schema_checker: schema_checker)).to be(false)
        expect(candidate.errors).to eq([model_error(code: :value_not_unique, target_column: "email")])
      end
    end

    context "when the schema finds a mistake" do
      let(:mapped_values) { {"email" => nil, "status" => "closed", "note" => nil} }

      it "is false, with that error" do
        expect(candidate.valid?(schema_checker: schema_checker)).to be(false)
        expect(candidate.errors.map { |error| error[:code] }).to eq([:value_missing])
      end
    end

    context "when both levels find the same mistake on the same column" do
      let(:mapped_values) { {"email" => nil, "status" => "closed", "note" => nil} }
      let(:errors_of) do
        ->(attributes:) { [model_error(code: :value_missing, target_column: "email", message: "model's words")] }
      end

      before { candidate.valid?(schema_checker: schema_checker) }

      it "keeps one error, the model's" do
        expect(candidate.errors).to eq([model_error(code: :value_missing, target_column: "email", message: "model's words")])
      end
    end

    context "when both levels find mistakes that differ" do
      let(:mapped_values) { {"email" => nil, "status" => "closed", "note" => nil} }
      let(:errors_of) { ->(attributes:) { [model_error(code: :value_invalid, target_column: "email")] } }

      before { candidate.valid?(schema_checker: schema_checker) }

      it "keeps both, the model's first" do
        expect(candidate.errors.map { |error| error[:code] }).to eq(%i[value_invalid value_missing])
      end
    end

    context "when the model finds a mistake on a column with the same code as the schema on another column" do
      let(:target_columns) do
        [build_target_column(name: "email", required: true), build_target_column(name: "phone", required: true)]
      end
      let(:mapped_values) { {"email" => nil, "phone" => nil} }
      let(:errors_of) { ->(attributes:) { [model_error(code: :value_missing, target_column: "email")] } }

      before { candidate.valid?(schema_checker: schema_checker) }

      it "keeps the schema's error for the other column" do
        expect(candidate.errors.map { |error| error[:target_column] }).to eq(%w[email phone])
      end
    end

    it "checks the schema on what the model record holds, not on the mapped values" do
      checker = instance_double(Pipeforge::RunProcessor::SchemaChecker, call: [])
      mapped_values_with_empty_default = {"email" => "ann@example.com", "status" => nil, "note" => nil}
      candidate = described_class.new(
        row_number: 1, mapped_values: mapped_values_with_empty_default,
        record_attributes: {"email" => "ann@example.com", "note" => nil},
        model_adapter: model_adapter
      )

      candidate.valid?(schema_checker: checker)

      expect(checker).to have_received(:call).with(attributes: {"email" => "ann@example.com", "note" => nil})
    end

    context "when the model's callbacks change a value during its validation" do
      let(:target_columns) { [build_target_column(name: "code", max_length: 3)] }
      let(:schema_checker) { Pipeforge::RunProcessor::SchemaChecker.new(target_schema: target_schema) }

      context "when the change makes a value fit" do
        let(:mapped_values) { {"code" => "abcd"} }
        let(:model_adapter) { FakeModelAdapter.new(changes_on_validation: ->(attributes:) { {"code" => "abc"} }) }

        it "does not report the value that was there before" do
          candidate.valid?(schema_checker: schema_checker)

          expect(candidate.errors).to eq([])
        end
      end

      context "when the change makes a value too long" do
        let(:mapped_values) { {"code" => "abc"} }
        let(:model_adapter) { FakeModelAdapter.new(changes_on_validation: ->(attributes:) { {"code" => "abcd"} }) }

        it "reports the value the model changed it to" do
          candidate.valid?(schema_checker: schema_checker)

          expect(candidate.errors.map { |error| error[:code] }).to eq([:value_too_long])
        end
      end
    end
  end

  describe "#failed_row" do
    let(:errors_of) { ->(attributes:) { [model_error(code: :value_not_unique, target_column: "email")] } }

    before { candidate.valid?(schema_checker: schema_checker) }

    it "has the row number and the transformed values" do
      expect(candidate.failed_row).to have_attributes(row_number: 7, mapped_values: mapped_values)
    end

    it "has each error with the origin it came from" do
      expect(candidate.failed_row.errors).to eq(
        [{origin: :model, code: :value_not_unique, message: "from the model", target_column: "email"}]
      )
    end

    context "when the schema finds a mistake as well" do
      let(:mapped_values) { {"email" => nil, "status" => "closed", "note" => nil} }
      let(:errors_of) { ->(attributes:) { [model_error(code: :value_invalid, target_column: "email")] } }

      it "has the model's error with the origin model and the schema's with the origin schema" do
        expect(candidate.failed_row.errors.map { |error| [error[:origin], error[:code]] }).to eq(
          [[:model, :value_invalid], [:schema, :value_missing]]
        )
      end
    end
  end

  describe "#load" do
    let(:database_error) do
      {origin: :database, code: :value_not_unique, message: "UNIQUE constraint failed", target_column: "email"}
    end

    context "when the write works" do
      it "is true, with no errors" do
        expect(candidate.load).to be(true)
        expect(candidate.errors).to eq([])
      end

      it "writes the record once, with the attributes it holds" do
        candidate.load

        expect(model_adapter.events).to eq([[:load, record_attributes]])
      end
    end

    context "when the database refuses the row" do
      let(:model_adapter) { FakeModelAdapter.new(load_errors_of: ->(attributes:) { [database_error] }) }

      it "is false, with the errors of the database" do
        expect(candidate.load).to be(false)
        expect(candidate.errors).to eq([database_error])
      end

      it "gives a failed row whose errors keep the origin database" do
        candidate.load

        expect(candidate.failed_row.errors).to eq([database_error])
      end
    end
  end
end
