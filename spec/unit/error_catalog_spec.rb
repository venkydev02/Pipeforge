# frozen_string_literal: true

# Each describe is one key of ERRORS, named as the code names it. The sentences are written here and nowhere else in
# the specs: the specs of the components that build an error compare it with the catalog's own call.
RSpec.describe Pipeforge::ErrorCatalog do
  # The origin and the value that failed are facts of every error; :model and "failed" stand for them.
  def build(key, **facts)
    described_class::ERRORS.fetch(key).call(origin: :model, target_column_name: "status", value: "failed", **facts)
  end

  describe "ERRORS" do
    it "has one key for each kind of error, named by its code and its kind" do
      expect(described_class::ERRORS.keys).to eq(
        %i[
          value_missing parent_missing value_not_unique value_too_long value_out_of_range_bytes
          value_out_of_range_digits value_out_of_range_float value_out_of_range value_not_allowed
          value_not_accepted_not_castable value_not_accepted_enum_label value_not_accepted_polymorphic_type
          value_invalid value_invalid_save_stopped database_error
        ]
      )
    end
  end

  describe "the shape of an error" do
    context "when the error has a column" do
      it "is a Hash of origin, code, kind, target_column_name, message, details and value, with the column before the sentence" do
        expect(build(:value_missing)).to eq(
          origin: :model, code: :value_missing, kind: nil, target_column_name: "status",
          message: "status: the value is required but empty", details: {}, value: "failed"
        )
      end
    end

    context "when the error is about the record as a whole" do
      it "has no column and its message is the sentence" do
        error = described_class::ERRORS.fetch(:value_missing).call(origin: :model, target_column_name: nil, value: nil)

        expect(error).to eq(
          origin: :model, code: :value_missing, kind: nil, target_column_name: nil, message: "the value is required but empty",
          details: {}, value: nil
        )
      end
    end

    context "when the database's text is given to a kind that it can refuse" do
      it "keeps it in the details as native_message" do
        expect(build(:value_not_unique, native_message: "duplicate key")[:details]).to eq(
          native_message: "duplicate key"
        )
      end
    end

    context "when the value that failed is not given" do
      it "is refused, because the value is a fact of every error" do
        expect { described_class::ERRORS.fetch(:value_missing).call(origin: :model, target_column_name: "status") }
          .to raise_error(ArgumentError, /value/)
      end
    end

    context "when the origin is not given" do
      it "is refused, because the origin is a fact of every error" do
        expect { described_class::ERRORS.fetch(:value_missing).call(target_column_name: "status", value: "failed") }
          .to raise_error(ArgumentError, /origin/)
      end
    end

    context "when a fact that the kind does not know is given" do
      it "is refused, so a wrong name is found at once" do
        expect { build(:value_out_of_range_bytes, bytes: 2, byte: 2) }.to raise_error(ArgumentError, /byte/)
      end
    end
  end

  describe "value_missing" do
    it "says the value is required but empty" do
      expect(build(:value_missing)[:message]).to eq("status: the value is required but empty")
    end
  end

  describe "parent_missing" do
    it "says the parent row does not exist" do
      expect(build(:parent_missing)).to include(code: :parent_missing, message: "status: the parent row does not exist")
    end
  end

  describe "value_not_unique" do
    it "says a row with the same value already exists" do
      expect(build(:value_not_unique)).to include(
        code: :value_not_unique, message: "status: a row with the same value already exists"
      )
    end
  end

  describe "value_too_long" do
    context "when the length and the maximum are given" do
      it "says both, and keeps them as the details" do
        expect(build(:value_too_long, length: 34, max_length: 20)).to eq(
          origin: :model, code: :value_too_long, kind: nil, target_column_name: "status",
          message: "status: the value has 34 characters, more than the 20 allowed",
          details: {length: 34, max_length: 20}, value: "failed"
        )
      end
    end

    context "when only the maximum is given" do
      it "says the maximum" do
        expect(build(:value_too_long, max_length: 20)).to include(
          message: "status: the value is longer than the 20 characters allowed", details: {max_length: 20}, value: "failed"
        )
      end
    end

    context "when neither is given" do
      it "says the value is longer than its column allows" do
        expect(build(:value_too_long)).to include(
          message: "status: the value is longer than its column allows", details: {}, value: "failed"
        )
      end
    end
  end

  describe "value_out_of_range_bytes" do
    it "has the code value_out_of_range with the kind bytes, and says the bytes" do
      expect(build(:value_out_of_range_bytes, bytes: 2)).to eq(
        origin: :model, code: :value_out_of_range, kind: :bytes, target_column_name: "status",
        message: "status: the value does not fit in 2 bytes", details: {bytes: 2}, value: "failed"
      )
    end

    it "needs the bytes" do
      expect { build(:value_out_of_range_bytes) }.to raise_error(ArgumentError, /bytes/)
    end
  end

  describe "value_out_of_range_digits" do
    it "has the kind digits, and says the digits allowed before the point" do
      expect(build(:value_out_of_range_digits, allowed_digits: 3)).to eq(
        origin: :model, code: :value_out_of_range, kind: :digits, target_column_name: "status",
        message: "status: the value has more than 3 digits before the point", details: {allowed_digits: 3}, value: "failed"
      )
    end
  end

  describe "value_out_of_range_float" do
    it "has the kind float, and says the value is larger than a float of the column can hold" do
      expect(build(:value_out_of_range_float)).to eq(
        origin: :model, code: :value_out_of_range, kind: :float, target_column_name: "status",
        message: "status: the value is larger than a float of this column can hold", details: {}, value: "failed"
      )
    end
  end

  describe "value_out_of_range" do
    it "has no kind, and says the value is outside what the column holds" do
      expect(build(:value_out_of_range)).to include(
        code: :value_out_of_range, kind: nil, message: "status: the value is outside what its column holds"
      )
    end
  end

  describe "value_not_allowed" do
    it "lists the labels, separated by commas, and keeps them as a list in the details" do
      expect(build(:value_not_allowed, labels: %w[draft placed])).to eq(
        origin: :model, code: :value_not_allowed, kind: nil, target_column_name: "status",
        message: "status: the value is not one of draft, placed", details: {labels: %w[draft placed]}, value: "failed"
      )
    end
  end

  describe "value_not_accepted_not_castable" do
    it "has the kind not_castable, and says the value cannot be given to the model" do
      expect(build(:value_not_accepted_not_castable)).to eq(
        origin: :model, code: :value_not_accepted, kind: :not_castable, target_column_name: "status",
        message: "status: the value cannot be given to the model", details: {}, value: "failed"
      )
    end
  end

  describe "value_not_accepted_enum_label" do
    it "has the kind enum_label, and says the value is not a label of the enum" do
      expect(build(:value_not_accepted_enum_label)).to eq(
        origin: :model, code: :value_not_accepted, kind: :enum_label, target_column_name: "status",
        message: "status: the value is not a label of the enum", details: {}, value: "failed"
      )
    end
  end

  describe "value_not_accepted_polymorphic_type" do
    it "has the kind polymorphic_type, and says the value is not a model of the application" do
      expect(build(:value_not_accepted_polymorphic_type)).to eq(
        origin: :model, code: :value_not_accepted, kind: :polymorphic_type, target_column_name: "status",
        message: "status: the value is not a model of the application", details: {}, value: "failed"
      )
    end
  end

  describe "value_invalid" do
    it "ends its sentence with the text of the model in brackets, and keeps it as native_message" do
      expect(build(:value_invalid, native_message: "signups are closed", error_type: :custom)).to eq(
        origin: :model, code: :value_invalid, kind: nil, target_column_name: "status",
        message: "status: the model does not accept the value (signups are closed)",
        details: {native_message: "signups are closed", error_type: :custom}, value: "failed"
      )
    end

    it "needs the native message" do
      expect { build(:value_invalid) }.to raise_error(ArgumentError, /native_message/)
    end
  end

  describe "value_invalid_save_stopped" do
    it "has the kind save_stopped, and ends its sentence with the text of the model in brackets" do
      expect(build(:value_invalid_save_stopped, native_message: "Failed to save")).to eq(
        origin: :model, code: :value_invalid, kind: :save_stopped, target_column_name: "status",
        message: "status: a callback of the model stopped the save (Failed to save)",
        details: {native_message: "Failed to save"}, value: "failed"
      )
    end
  end

  describe "database_error" do
    it "ends its sentence with the text of the database in brackets, and keeps it as native_message" do
      expect(build(:database_error, native_message: "disk is full")).to eq(
        origin: :model, code: :database_error, kind: nil, target_column_name: "status",
        message: "status: the database refused the row (disk is full)", details: {native_message: "disk is full"}, value: "failed"
      )
    end
  end
end
