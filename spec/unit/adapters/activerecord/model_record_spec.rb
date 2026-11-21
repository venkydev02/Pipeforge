# frozen_string_literal: true

# The model record wraps a record of ActiveRecord, a third-party gem, so every example builds a real model over a real
# table of the PostgreSQL test database, made by define_model in the example and dropped after it, and nothing is
# replaced by a double: every refusal of the database is a real one, and a change in a new version of ActiveRecord
# shows here. The models are named for the fact they show. The only model taken from spec/support/active_record_helper.rb
# is the parent AdapterSpecModels::Company. ErrorCatalog is plain data of ours, so it is called for real: an error of
# the record is compared with the catalog's call for the same input.
# An example that no break fails alone is kept for what the rule accepts or reports (contract only).
RSpec.describe Pipeforge::ActiveRecordModelRecord do
  subject(:model_record) { described_class.new(record: record) }

  let(:record) { model.new(attributes) }
  let(:attributes) { {} }

  # The error of the ErrorCatalog for the same key and the same facts.
  def catalog_error(key:, origin:, target_column_name:, value:, **facts)
    Pipeforge::ErrorCatalog::ERRORS.fetch(key).call(
      origin: origin, target_column_name: target_column_name, value: value, **facts
    )
  end

  def define_model_with_required_email
    define_model(name: "ModelWithRequiredEmail", columns: ->(table) { table.string :email }) do
      validates :email, presence: true
    end
  end

  def define_model_with_maximum_length
    define_model(name: "ModelWithMaximumLength", columns: ->(table) { table.string :code }) do
      validates :code, length: {maximum: 3}
    end
  end

  def define_model_with_unique_email
    define_model(name: "ModelWithUniqueEmail", columns: ->(table) { table.string :email }) do
      validates :email, uniqueness: true
    end
  end

  def define_model_with_required_parent
    define_model(name: "ModelWithRequiredParent", columns: ->(table) { table.bigint :company_id }) do
      belongs_to :company, class_name: "AdapterSpecModels::Company", optional: false
    end
  end

  def define_model_with_required_polymorphic_parent
    define_model(
      name: "ModelWithRequiredPolymorphicParent",
      columns: lambda do |table|
        table.integer :owner_id
        table.string :owner_type
      end
    ) do
      belongs_to :owner, polymorphic: true, optional: false
    end
  end

  def define_model_with_numeric_limit
    define_model(
      name: "ModelWithNumericLimit",
      columns: lambda do |table|
        table.integer :seats
        table.decimal :fee, precision: 5, scale: 2
      end
    ) do
      validates :seats, numericality: {less_than: 100}
      validates :fee, numericality: {less_than: 100}
    end
  end

  def define_model_with_base_error
    define_model(name: "ModelWithBaseError", columns: ->(table) { table.string :email }) do
      validate { errors.add(:base, :invalid, message: "closed") }
    end
  end

  def define_model_with_non_column_error
    define_model(name: "ModelWithNonColumnError", columns: ->(table) { table.string :email }) do
      attr_accessor :nickname

      validate { errors.add(:nickname, :invalid) }
    end
  end

  def define_model_with_loose_length_error
    define_model(name: "ModelWithLooseLengthError", columns: ->(table) { table.string :email }) do
      validate { errors.add(:email, :too_long, message: "is far too long") }
    end
  end

  def define_model_with_two_errors_on_one_column
    define_model(name: "ModelWithTwoErrorsOnOneColumn", columns: ->(table) { table.string :email }) do
      validate { errors.add(:email, :invalid, message: "first problem") }
      validate { errors.add(:email, :invalid, message: "second problem") }
    end
  end

  def define_model_with_two_errors_on_two_columns
    define_model(
      name: "ModelWithTwoErrorsOnTwoColumns",
      columns: lambda do |table|
        table.string :email
        table.string :code
      end
    ) do
      validate { errors.add(:email, :invalid) }
      validate { errors.add(:code, :invalid) }
    end
  end

  def define_model_with_stripped_email
    define_model(name: "ModelWithStrippedEmail", columns: ->(table) { table.string :email }) do
      before_validation { self.email = email.strip unless email.nil? }
    end
  end

  def define_model_with_typed_columns
    define_model(
      name: "ModelWithTypedColumns",
      columns: lambda do |table|
        table.integer :seats
        table.decimal :fee, precision: 5, scale: 2
        table.date :starts_on
      end
    )
  end

  def define_model_with_email_and_presence
    define_model(name: "ModelWithEmailAndPresence", columns: ->(table) { table.string :email }) do
      validates :email, presence: true
    end
  end

  def define_model_with_unique_index
    define_model(name: "ModelWithUniqueIndex", columns: ->(table) { table.string :email, index: {unique: true} })
  end

  def define_model_with_required_column
    define_model(name: "ModelWithRequiredColumn", columns: ->(table) { table.string :email, null: false })
  end

  def define_model_with_required_column_and_presence
    define_model(name: "ModelWithRequiredColumnAndPresence", columns: ->(table) { table.string :email, null: false }) do
      validates :email, presence: true
    end
  end

  def define_model_with_foreign_key
    define_model(
      name: "ModelWithForeignKey",
      columns: ->(table) { table.bigint :company_id }
    ).tap do |model|
      ActiveRecord::Base.connection.add_foreign_key(model.table_name, :companies, column: :company_id)
    end
  end

  def define_model_with_short_string
    define_model(name: "ModelWithShortString", columns: ->(table) { table.string :code, limit: 3 })
  end

  def define_model_with_small_numeric
    define_model(name: "ModelWithSmallNumeric", columns: ->(table) { table.decimal :fee, precision: 3, scale: 0 })
  end

  def define_model_with_check_constraint
    define_model(name: "ModelWithCheckConstraint", columns: ->(table) { table.integer :age }).tap do |model|
      ActiveRecord::Base.connection.execute(
        "ALTER TABLE #{model.table_name} ADD CONSTRAINT age_is_positive CHECK (age > 0)"
      )
    end
  end

  def define_model_with_stopping_callback
    define_model(name: "ModelWithStoppingCallback", columns: ->(table) { table.string :note }) do
      before_save { throw :abort }
    end
  end

  describe "#record" do
    let(:model) { define_model_with_required_email }

    # contract only
    it "is the record given at build" do
      expect(model_record.record).to be(record)
    end
  end

  describe "#errors" do
    let(:model) { define_model_with_required_email }

    # contract only
    it "is an empty Hash when the model record is just built" do
      expect(model_record.errors).to eq({})
    end
  end

  describe "#add_error" do
    let(:model) { define_model_with_required_email }
    let(:email_error) do
      catalog_error(key: :value_missing, origin: :model, target_column_name: "email", value: nil)
    end
    let(:other_email_error) do
      catalog_error(key: :value_not_unique, origin: :model, target_column_name: "email", value: "a@example.com")
    end

    context "when the error is for the column email" do
      before { model_record.add_error(error: email_error) }

      # contract only
      it "keeps it under the key email" do
        expect(model_record.errors).to eq({"email" => email_error})
      end
    end

    context "when two errors are for the column email" do
      before do
        model_record.add_error(error: email_error)
        model_record.add_error(error: other_email_error)
      end

      it "keeps the first" do
        expect(model_record.errors).to eq({"email" => email_error})
      end
    end

    context "when the error is the Hash that to_h gives for a catalog error" do
      it "raises ArgumentError" do
        expect { model_record.add_error(error: email_error.to_h) }.to raise_error(ArgumentError)
      end
    end
  end

  describe "#valid?" do
    describe "the answer" do
      let(:model) { define_model_with_required_email }

      context "when the model's validations accept the record" do
        let(:attributes) { {email: "a@example.com"} }

        # contract only
        it "is true and #errors is empty" do
          expect(model_record.valid?).to be(true)
          expect(model_record.errors).to eq({})
        end

        context "and an error was added before with add_error" do
          before do
            model_record.add_error(
              error: catalog_error(key: :value_not_accepted_not_castable, origin: :model, target_column_name: "email", value: "x")
            )
          end

          it "is false" do
            expect(model_record.valid?).to be(false)
          end
        end
      end

      context "when a validation refuses the record" do
        let(:attributes) { {email: nil} }

        # contract only
        it "is false" do
          expect(model_record.valid?).to be(false)
        end
      end
    end

    describe "the errors it keeps" do
      let(:model) { define_model_with_required_email }
      let(:attributes) { {email: nil} }
      let(:earlier_error) do
        catalog_error(key: :value_not_accepted_not_castable, origin: :model, target_column_name: "email", value: "x")
      end

      context "when an error for email was added before and a validation refuses email" do
        before do
          model_record.add_error(error: earlier_error)
          model_record.valid?
        end

        it "keeps the error added before and does not add the model's error for email" do
          expect(model_record.errors).to eq({"email" => earlier_error})
        end
      end
    end

    describe "the error for one model error" do
      subject(:error) do
        model_record.valid?
        model_record.errors.fetch(target_column_name)
      end

      context "when email is nil on a model that validates presence of email" do
        let(:model) { define_model_with_required_email }
        let(:target_column_name) { "email" }

        # contract only
        it "is value_missing with origin model and value nil" do
          expect(error).to eq(
            catalog_error(
              key: :value_missing, origin: :model, target_column_name: "email", value: nil, native_message: "can't be blank"
            )
          )
        end
      end

      context "when code is \"abcdef\" on a model that validates length maximum 3" do
        let(:model) { define_model_with_maximum_length }
        let(:attributes) { {code: "abcdef"} }
        let(:target_column_name) { "code" }

        it "is value_too_long with length 6 and max_length 3, and the value" do
          expect(error).to eq(
            catalog_error(
              key: :value_too_long, origin: :model, target_column_name: "code", value: "abcdef", length: 6, max_length: 3,
              native_message: "is too long (maximum is 3 characters)"
            )
          )
        end
      end

      context "when email is one that a row of the table already has, on a model that validates uniqueness" do
        let(:model) { define_model_with_unique_email }
        let(:attributes) { {email: "a@example.com"} }
        let(:target_column_name) { "email" }

        before { model.create!(email: "a@example.com") }

        it "is value_not_unique with the value" do
          expect(error).to eq(
            catalog_error(
              key: :value_not_unique, origin: :model, target_column_name: "email", value: "a@example.com",
              native_message: "has already been taken"
            )
          )
        end
      end

      context "when the model has a required parent" do
        let(:model) { define_model_with_required_parent }
        let(:target_column_name) { "company_id" }

        context "and company_id is nil" do
          let(:attributes) { {company_id: nil} }

          it "is value_missing for the foreign key column with value nil" do
            expect(error).to eq(
              catalog_error(
                key: :value_missing, origin: :model, target_column_name: "company_id", value: nil, native_message: "must exist"
              )
            )
          end
        end

        context "and company_id is 999999, a company that does not exist" do
          let(:attributes) { {company_id: 999_999} }

          it "is parent_missing for the foreign key column with the value 999999" do
            expect(error).to eq(
              catalog_error(
                key: :parent_missing, origin: :model, target_column_name: "company_id", value: 999_999, native_message: "must exist"
              )
            )
          end
        end
      end

      context "when the model has a required polymorphic parent" do
        let(:model) { define_model_with_required_polymorphic_parent }
        let(:target_column_name) { "owner_id" }

        context "and owner_id is 999999 and owner_type is AdapterSpecModels::Company" do
          let(:attributes) { {owner_id: 999_999, owner_type: "AdapterSpecModels::Company"} }

          # contract only
          it "is parent_missing for owner_id with the value 999999" do
            expect(error).to eq(
              catalog_error(
                key: :parent_missing, origin: :model, target_column_name: "owner_id", value: 999_999, native_message: "must exist"
              )
            )
          end
        end
      end

      context "when a validation that is not one of the shared codes refuses the value" do
        let(:model) { define_model_with_numeric_limit }

        context "and seats is 100000" do
          let(:attributes) { {seats: 100_000} }
          let(:target_column_name) { "seats" }

          # contract only
          it "is value_invalid with native_message and error_type less_than, and the value" do
            expect(error).to eq(
              catalog_error(
                key: :value_invalid, origin: :model, target_column_name: "seats", value: 100_000,
                native_message: "must be less than 100", error_type: :less_than
              )
            )
          end
        end

        context "and fee is 1000.5" do
          let(:attributes) { {fee: 1000.5} }
          let(:target_column_name) { "fee" }

          it "has the value \"1000.5\", in JSON types" do
            expect(error.value).to eq("1000.5")
          end
        end
      end

      context "when a validation adds an error on :base" do
        subject(:error) do
          model_record.valid?
          model_record.errors.fetch(nil)
        end

        let(:model) { define_model_with_base_error }

        it "is value_invalid under the key nil, with target_column_name nil and value nil" do
          expect(error).to eq(
            catalog_error(
              key: :value_invalid, origin: :model, target_column_name: nil, value: nil, native_message: "closed",
              error_type: :invalid
            )
          )
        end
      end
    end

    describe "the errors of two columns" do
      let(:model) { define_model_with_two_errors_on_two_columns }

      before { model_record.valid? }

      it "has one error for each column, in the order the model reports them" do
        expect(model_record.errors.keys).to eq(%w[email code])
      end
    end
  end

  describe "#load" do
    describe "a row that the table takes" do
      let(:model) { define_model_with_required_email }
      let(:attributes) { {email: "a@example.com"} }

      # contract only
      it "is true and the row is in the table" do
        expect(model_record.load).to be(true)
        expect(model.pluck(:email)).to eq(["a@example.com"])
      end

      context "when valid? added a model error before" do
        let(:model) { define_model_with_email_and_presence }
        let(:attributes) { {email: nil} }

        before { model_record.valid? }

        it "leaves #errors empty after the load" do
          model_record.load

          expect(model_record.errors).to eq({})
        end
      end
    end

    describe "a refusal of the database" do
      subject(:entry) do
        model_record.load
        model_record.errors.fetch(nil)
      end

      # The entry of the catalog for the key, with the text of the database as native_message.
      def database_entry_of(key:)
        catalog_error(
          key: key, origin: :database, target_column_name: nil, value: nil, native_message: entry.details[:native_message]
        )
      end

      context "when email is one that the unique index already holds" do
        let(:model) { define_model_with_unique_index }
        let(:attributes) { {email: "a@example.com"} }

        before { model.create!(email: "a@example.com") }

        it "is false" do
          expect(model_record.load).to be(false)
        end

        it "is value_not_unique with the text of the database" do
          expect(entry).to eq(database_entry_of(key: :value_not_unique))
          expect(entry.details.fetch(:native_message)).to include("unique")
        end
      end

      context "when email is nil on a NOT NULL column" do
        let(:model) { define_model_with_required_column }

        it "is value_missing with the text of the database" do
          expect(entry).to eq(database_entry_of(key: :value_missing))
          expect(entry.details.fetch(:native_message)).to include("null value")
        end
      end

      context "when company_id is a company that does not exist, on a foreign key" do
        let(:model) { define_model_with_foreign_key }
        let(:attributes) { {company_id: 999_999} }

        it "is parent_missing with the text of the database" do
          expect(entry).to eq(database_entry_of(key: :parent_missing))
          expect(entry.details.fetch(:native_message)).to include("foreign key")
        end
      end

      context "when code has five characters in a column of three" do
        let(:model) { define_model_with_short_string }
        let(:attributes) { {code: "abcde"} }

        it "is value_too_long with the text of the database" do
          expect(entry).to eq(database_entry_of(key: :value_too_long))
          expect(entry.details.fetch(:native_message)).to include("too long")
        end
      end

      context "when fee is 99999 in a decimal(3, 0) column" do
        let(:model) { define_model_with_small_numeric }
        let(:attributes) { {fee: 99_999} }

        it "is value_out_of_range with the text of the database" do
          expect(entry).to eq(database_entry_of(key: :value_out_of_range))
          expect(entry.details.fetch(:native_message)).to include("overflow")
        end
      end

      context "when age is -1 against the constraint CHECK (age > 0)" do
        let(:model) { define_model_with_check_constraint }
        let(:attributes) { {age: -1} }

        it "is database_error with the text of the database" do
          expect(entry).to eq(database_entry_of(key: :database_error))
          expect(entry.details.fetch(:native_message)).to include("check constraint")
        end
      end

      context "when a model error is in #errors from valid? and the database refuses the load" do
        let(:model) { define_model_with_required_column_and_presence }

        before { model_record.valid? }

        # contract only
        it "has the entry of the database only" do
          model_record.load

          expect(model_record.errors.keys).to eq([nil])
          expect(entry.origin).to eq(:database)
        end
      end
    end

    describe "a callback that stops the save" do
      let(:model) { define_model_with_stopping_callback }

      it "is value_invalid_save_stopped with origin model, no column, value nil and the text of RecordNotSaved" do
        model_record.load

        expect(model_record.errors).to eq(
          {
            nil => catalog_error(
              key: :value_invalid_save_stopped, origin: :model, target_column_name: nil, value: nil,
              native_message: "Failed to save the record"
            )
          }
        )
      end
    end

    describe "a transaction of the consumer" do
      let(:model) { define_model_with_unique_index }
      let(:attributes) { {email: "first@example.com"} }

      context "when a row they wrote before is in it and the database refuses the row" do
        before do
          model.transaction do
            model.create!(email: "first@example.com")
            model_record.load
            model.create!(email: "second@example.com")
          end
        end

        it "keeps the earlier row and the transaction can still be used afterwards" do
          expect(model.order(:id).pluck(:email)).to eq(["first@example.com", "second@example.com"])
        end
      end
    end
  end

  describe "#attributes" do
    let(:model) { define_model_with_typed_columns }

    context "when seats is \"12\" and fee is \"12.5\"" do
      let(:attributes) { {seats: "12", fee: "12.5"} }

      it "has seats 12 and fee as a BigDecimal, cast to the column types" do
        expect(model_record.attributes).to include("seats" => 12, "fee" => BigDecimal("12.5"))
      end
    end

    context "when before_validation strips the email and valid? was called" do
      let(:model) { define_model_with_stripped_email }
      let(:attributes) { {email: "  a@example.com  "} }

      before { model_record.valid? }

      # contract only
      it "has the stripped email" do
        expect(model_record.attributes.fetch("email")).to eq("a@example.com")
      end
    end
  end

  describe "#json_attributes" do
    let(:model) { define_model_with_typed_columns }

    context "when starts_on is \"2024-02-03\" and fee is 12.5" do
      let(:attributes) { {starts_on: "2024-02-03", fee: 12.5} }

      it "has starts_on \"2024-02-03\" and fee \"12.5\", as text" do
        expect(model_record.json_attributes).to include("starts_on" => "2024-02-03", "fee" => "12.5")
      end
    end
  end
end
