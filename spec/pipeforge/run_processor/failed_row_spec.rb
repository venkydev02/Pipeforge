# frozen_string_literal: true

# A failed row holds the errors of its row as the error objects that the ErrorCatalog built, and gives the whole row as plain
# JSON types with #to_h.
RSpec.describe Pipeforge::RunProcessor::FailedRow do
  subject(:failed_row) { described_class.new(row_number: 4, attributes: {"status" => "far too long"}, errors: errors) }

  # An error as the ErrorCatalog builds it.
  def catalog_error(key, **facts)
    Pipeforge::ErrorCatalog::ERRORS.fetch(key).call(**facts)
  end

  let(:too_long_error) do
    catalog_error(
      :value_too_long, origin: :schema, target_column_name: "status", value: "far too long", length: 12, max_length: 5
    )
  end
  let(:missing_error) { catalog_error(:value_missing, origin: :model, target_column_name: "email", value: nil) }
  let(:errors) { [too_long_error, missing_error] }

  describe "#errors" do
    it "holds the error objects it was given, as they are" do
      expect(failed_row.errors).to eq([too_long_error, missing_error])
    end

    it "holds objects that the ErrorCatalog built" do
      expect(failed_row.errors.map { |error| Pipeforge::ErrorCatalog.error?(candidate: error) }).to eq([true, true])
    end
  end

  describe "#to_h" do
    it "gives the row number and the attributes" do
      expect(failed_row.to_h).to include(row_number: 4, attributes: {"status" => "far too long"})
    end

    context "when the row has two errors" do
      it "gives each error as the Hash of its seven fields, in the same order" do
        expect(failed_row.to_h[:errors]).to eq(
          [
            {
              origin: :schema, code: :value_too_long, kind: nil, target_column_name: "status",
              message: "status: the value has 12 characters, more than the 5 allowed",
              details: {length: 12, max_length: 5}, value: "far too long"
            },
            {
              origin: :model, code: :value_missing, kind: nil, target_column_name: "email",
              message: "email: the value is required but empty", details: {}, value: nil
            }
          ]
        )
      end
    end

    context "when the row has one error" do
      let(:errors) { [missing_error] }

      it "gives that error as a Hash" do
        expect(failed_row.to_h[:errors]).to eq([missing_error.to_h])
      end
    end

    it "leaves the errors of the failed row as objects" do
      failed_row.to_h

      expect(failed_row.errors).to eq([too_long_error, missing_error])
    end
  end
end
