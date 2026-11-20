# frozen_string_literal: true

RSpec.describe Pipeforge::ActiveRecordModelRecord do
  subject(:model_record) { target.build_record(attributes: attributes) }

  let(:target) { Pipeforge::ActiveRecordTarget.new(target_model_name: "AdapterSpecModels::Membership") }
  let(:company) { AdapterSpecModels::Company.create!(name: "Acme") }
  let(:attributes) { {"email" => "ann@example.com", "tier" => "basic", "company_id" => company.id} }

  def codes_of(model_record)
    model_record.errors.values.map { |error| error[:code] }
  end

  # The error that the record promises is the one the ErrorCatalog builds for the mistake, with the origin and the
  # value that failed.
  def catalog_error(key, target_column_name:, origin:, value:, **facts)
    Pipeforge::ErrorCatalog::ERRORS.fetch(key)
      .call(origin: origin, target_column_name: target_column_name, value: value, **facts)
  end

  describe "#record" do
    it "is the unsaved record" do
      expect(model_record.record).to be_a(AdapterSpecModels::Membership).and have_attributes(new_record?: true)
    end
  end

  describe "#errors" do
    it "is empty before the record is validated" do
      expect(model_record.errors.values).to eq([])
    end
  end

  describe "#attributes" do
    let(:attributes) do
      {"email" => "ann@example.com", "seats" => "12", "fee" => "999.999", "tier" => "pro", "company_id" => company.id}
    end

    it "gives the values cast to the types of the columns" do
      expect(model_record.attributes).to include("seats" => 12, "tier" => "pro", "company_id" => company.id)
    end

    it "gives a decimal as the number the database would store, rounded to the scale" do
      expect(model_record.attributes["fee"]).to eq(BigDecimal("1000.00"))
    end

    it "includes the columns that were not given, as nil" do
      expect(model_record.attributes).to include("id" => nil)
    end

    context "when the model's callbacks change a value" do
      let(:attributes) { {"email" => "  ann@example.com  ", "tier" => "basic", "company_id" => company.id} }

      it "gives the value as it was given before the validation" do
        expect(model_record.attributes["email"]).to eq("  ann@example.com  ")
      end

      it "gives the changed value after the validation" do
        model_record.valid?

        expect(model_record.attributes["email"]).to eq("ann@example.com")
      end
    end

    context "when an enum label is not one the model knows" do
      let(:attributes) { {"email" => "ann@example.com", "tier" => "gold", "company_id" => company.id} }

      it "does not include the label, which the target did not give the record" do
        expect(model_record.attributes["tier"]).to be_nil
      end
    end

    context "when a json column holds a text that is not JSON" do
      let(:target) { Pipeforge::ActiveRecordTarget.new(target_model_name: "AdapterSpecModels::Profile") }
      let(:attributes) { {"name" => "ann", "settings" => "{oops"} }

      it "does not include the text, which the target did not give the record" do
        expect(model_record.attributes["settings"]).to be_nil
      end
    end
  end

  describe "#json_attributes" do
    let(:attributes) do
      {"email" => "ann@example.com", "seats" => "12", "fee" => "999.999", "tier" => "pro", "company_id" => company.id}
    end

    it "gives an integer as a number" do
      expect(model_record.json_attributes).to include("seats" => 12, "company_id" => company.id)
    end

    it "gives a decimal as a text" do
      expect(model_record.json_attributes["fee"]).to eq("1000.0")
    end

    it "has the columns of the attributes" do
      expect(model_record.json_attributes.keys).to eq(model_record.attributes.keys)
    end

    context "with a date column" do
      let(:target) { Pipeforge::ActiveRecordTarget.new(target_model_name: "AdapterSpecModels::Event") }
      let(:attributes) { {"starts_on" => "2024-01-31"} }

      it "gives a date as its ISO text" do
        expect(model_record.json_attributes["starts_on"]).to eq("2024-01-31")
      end
    end

    context "when the model's callbacks change a value" do
      let(:attributes) { {"email" => "  ann@example.com  ", "tier" => "basic", "company_id" => company.id} }

      it "gives the changed value after the validation" do
        model_record.valid?

        expect(model_record.json_attributes["email"]).to eq("ann@example.com")
      end
    end
  end

  describe "a polymorphic type that names no model" do
    let(:target) { Pipeforge::ActiveRecordTarget.new(target_model_name: "AdapterSpecModels::CommentWithRequiredParent") }
    let(:attributes) { {"commentable_id" => 1, "commentable_type" => "Post"} }

    it "has the error of the type column as soon as the record is built" do
      expect(model_record.errors.values).to contain_exactly(
        include(origin: :model, code: :value_not_accepted, target_column_name: "commentable_type")
      )
    end

    it "has the error of the catalog, with the type that failed as the value" do
      expect(model_record.errors["commentable_type"]).to eq(
        catalog_error(
          :value_not_accepted_polymorphic_type, target_column_name: "commentable_type", origin: :model, value: "Post"
        )
      )
    end

    it "also has the model's own error of the id column, one error for each column" do
      model_record.valid?

      expect(model_record.errors.values.map { |error| [error[:target_column_name], error[:code]] }).to eq(
        [["commentable_type", :value_not_accepted], ["commentable_id", :parent_missing]]
      )
    end

    context "when the type names a model whose parent does not exist" do
      let(:attributes) { {"commentable_id" => 999_999, "commentable_type" => "AdapterSpecModels::Company"} }

      it "still reports the missing parent, as parent_missing" do
        model_record.valid?

        expect(model_record.errors.values).to contain_exactly(
          include(code: :parent_missing, target_column_name: "commentable_id")
        )
      end
    end
  end

  describe "#add_error" do
    def entry(code:, target_column_name:, origin: :model)
      {
        origin: origin, code: code, kind: nil, target_column_name: target_column_name, message: "a message",
        details: {}, value: nil
      }
    end

    it "adds the error of a column" do
      model_record.add_error(**entry(code: :value_invalid, target_column_name: "email"))

      expect(model_record.errors).to eq("email" => entry(code: :value_invalid, target_column_name: "email"))
    end

    it "keeps the first error of a column and ignores a later one" do
      model_record.add_error(**entry(code: :value_invalid, target_column_name: "email"))
      model_record.add_error(**entry(code: :value_missing, target_column_name: "email", origin: :schema))

      expect(model_record.errors.values.map { |error| error[:code] }).to eq([:value_invalid])
    end

    it "keeps the errors of different columns, in the order they were added" do
      model_record.add_error(**entry(code: :value_invalid, target_column_name: "seats"))
      model_record.add_error(**entry(code: :value_missing, target_column_name: "email"))

      expect(model_record.errors.keys).to eq(%w[seats email])
    end

    it "keeps one error for the record as a whole, the one that has no column" do
      model_record.add_error(**entry(code: :value_invalid, target_column_name: nil))
      model_record.add_error(**entry(code: :database_error, target_column_name: nil, origin: :database))

      expect(model_record.errors.values.map { |error| error[:code] }).to eq([:value_invalid])
    end
  end

  describe "#valid?" do
    context "when the model finds no mistake" do
      it "is true, with no errors" do
        expect(model_record.valid?).to be(true)
        expect(model_record.errors.values).to eq([])
      end
    end

    context "when a required value is blank" do
      let(:attributes) { {"email" => nil, "tier" => "basic", "company_id" => company.id} }

      it "is false, with value_missing for that column" do
        expect(model_record.valid?).to be(false)
        expect(model_record.errors.values).to contain_exactly(include(code: :value_missing, target_column_name: "email"))
      end

      it "gives the error of the catalog, with no value" do
        model_record.valid?

        expect(model_record.errors["email"]).to eq(
          catalog_error(:value_missing, target_column_name: "email", origin: :model, value: nil)
        )
      end
    end

    context "when a value is too long" do
      let(:attributes) { {"email" => "a-very-long-address@example.com", "tier" => "basic", "company_id" => company.id} }

      it "gives value_too_long for that column, with the maximum, the length and the value that failed" do
        model_record.valid?

        expect(model_record.errors["email"]).to eq(
          catalog_error(
            :value_too_long, target_column_name: "email", origin: :model, value: "a-very-long-address@example.com",
            length: 31, max_length: 20
          )
        )
      end
    end

    context "when a value is already taken by a row of the table" do
      before do
        AdapterSpecModels::Membership.create!(email: "ann@example.com", tier: :basic, company: company)
      end

      it "gives value_not_unique for that column" do
        model_record.valid?

        expect(model_record.errors.values).to contain_exactly(include(code: :value_not_unique, target_column_name: "email"))
      end
    end

    context "when the parent does not exist" do
      let(:attributes) { {"email" => "ann@example.com", "tier" => "basic", "company_id" => 999_999} }

      it "gives parent_missing for the foreign key column" do
        model_record.valid?

        expect(model_record.errors.values).to contain_exactly(include(code: :parent_missing, target_column_name: "company_id"))
      end
    end

    context "when no parent is given" do
      let(:attributes) { {"email" => "ann@example.com", "tier" => "basic", "company_id" => nil} }

      it "gives value_missing for the foreign key column, because the value is empty" do
        model_record.valid?

        expect(model_record.errors.values).to contain_exactly(include(code: :value_missing, target_column_name: "company_id"))
      end
    end

    context "when the model reports a length error on an attribute that is not a column, with no maximum" do
      let(:target) { Pipeforge::ActiveRecordTarget.new(target_model_name: "AdapterSpecModels::LooseLengthAccount") }
      let(:attributes) { {"email" => "ann@example.com"} }

      it "gives value_too_long with no maximum, no length and no value" do
        model_record.valid?

        expect(model_record.errors["alias_name"]).to eq(
          catalog_error(:value_too_long, target_column_name: "alias_name", origin: :model, value: nil)
        )
      end
    end

    context "when another validation fails" do
      let(:attributes) { {"email" => "ann@example.com", "tier" => "basic", "company_id" => company.id, "seats" => 200_000} }

      it "gives value_invalid for that column, with the text of the model as a fact and the value that failed" do
        model_record.valid?

        expect(model_record.errors["seats"]).to eq(
          catalog_error(
            :value_invalid, target_column_name: "seats", origin: :model, value: 200_000,
            native_message: "must be less than 100000", error_type: :less_than
          )
        )
      end
    end

    context "when the mistake is on the record as a whole" do
      let(:attributes) { {"email" => "closed@example.com", "tier" => "basic", "company_id" => company.id} }

      it "gives value_invalid with no column and no value" do
        model_record.valid?

        expect(model_record.errors[nil]).to eq(
          catalog_error(
            :value_invalid, target_column_name: nil, origin: :model, value: nil,
            native_message: "signups are closed for this email", error_type: "signups are closed for this email"
          )
        )
      end
    end

    context "when an enum label is not one the model knows" do
      let(:attributes) { {"email" => "ann@example.com", "tier" => "gold", "company_id" => company.id} }

      it "gives value_not_accepted for that column" do
        expect(model_record.valid?).to be(false)
        expect(model_record.errors.values).to contain_exactly(include(origin: :model, code: :value_not_accepted, target_column_name: "tier"))
      end

      it "does not add the blank value the model sees as a second mistake" do
        model_record.valid?

        expect(codes_of(model_record)).not_to include(:value_missing)
      end
    end

    context "when an unknown enum label comes with mistakes in other columns" do
      let(:attributes) { {"email" => nil, "tier" => "gold", "company_id" => company.id} }

      it "reports both" do
        model_record.valid?

        expect(model_record.errors.values.map { |error| [error[:target_column_name], error[:code]] }).to contain_exactly(
          ["tier", :value_not_accepted], ["email", :value_missing]
        )
      end
    end

    context "when a json column holds a text that is not JSON" do
      let(:target) { Pipeforge::ActiveRecordTarget.new(target_model_name: "AdapterSpecModels::Profile") }
      let(:attributes) { {"name" => "ann", "settings" => "{oops"} }

      it "is false" do
        expect(model_record.valid?).to be(false)
      end

      it "gives value_not_accepted for that column" do
        model_record.valid?

        expect(model_record.errors.values).to contain_exactly(include(origin: :model, code: :value_not_accepted, target_column_name: "settings"))
      end

      context "and the model also requires the column" do
        let(:target) do
          Pipeforge::ActiveRecordTarget.new(target_model_name: "AdapterSpecModels::ProfileWithRequiredSettings")
        end

        it "gives value_not_accepted and not the blank value the model sees as a second mistake" do
          model_record.valid?

          expect(model_record.errors.values).to contain_exactly(
            include(origin: :model, code: :value_not_accepted, target_column_name: "settings")
          )
        end
      end

      context "and the text is the JSON null" do
        let(:attributes) { {"name" => "ann", "settings" => "null"} }

        it "is true, with no errors" do
          expect(model_record.valid?).to be(true)
          expect(model_record.errors.values).to eq([])
        end
      end

      context "and a second json column holds a text that is not JSON" do
        let(:attributes) { {"name" => "ann", "settings" => "{oops", "extras" => "hello"} }

        it "reports both columns" do
          model_record.valid?

          expect(model_record.errors.values.map { |error| error[:target_column_name] }).to contain_exactly("settings", "extras")
        end
      end

      context "and another column has a mistake" do
        let(:attributes) { {"name" => nil, "settings" => "{oops"} }

        it "reports both mistakes" do
          model_record.valid?

          expect(model_record.errors.values.map { |error| [error[:target_column_name], error[:code]] }).to contain_exactly(
            ["settings", :value_not_accepted], ["name", :value_missing]
          )
        end
      end
    end

    context "when it is called again" do
      let(:attributes) { {"email" => nil, "tier" => "basic", "company_id" => company.id} }

      it "keeps one error for each column" do
        model_record.valid?
        model_record.valid?

        expect(model_record.errors.values.map { |error| error[:target_column_name] }).to eq(%w[email])
      end
    end

    context "when the target already gave the record an error for a column" do
      let(:attributes) { {"email" => "ann@example.com", "tier" => "gold", "company_id" => company.id} }

      it "keeps that error and does not clear it" do
        model_record.valid?

        expect(model_record.errors["tier"]).to include(code: :value_not_accepted)
      end
    end
  end

  describe "#load" do
    subject(:model_record) { target.build_record(attributes: attributes) }

    let(:target) { Pipeforge::ActiveRecordTarget.new(target_model_name: "AdapterSpecModels::Account") }
    let(:attributes) { {"email" => "ann@example.com", "nickname" => "ann", "company_id" => company.id} }

    context "when the table takes the row" do
      it "is true, with no errors" do
        expect(model_record.load).to be(true)
        expect(model_record.errors.values).to eq([])
      end

      it "saves the record" do
        model_record.load

        expect(AdapterSpecModels::Account.where(email: "ann@example.com").count).to eq(1)
      end

      it "does not run the model's validations again" do
        validating_target = Pipeforge::ActiveRecordTarget.new(target_model_name: "AdapterSpecModels::Membership")
        record = validating_target.build_record(attributes: {"email" => nil, "tier" => "basic"})

        expect(record.load).to be(false)
        expect(record.errors.values.map { |error| error[:code] }).to eq([:value_missing])
        expect(record.record.errors).to be_empty
      end
    end

    context "when the table already has the value of a unique index" do
      before { AdapterSpecModels::Account.create!(email: "ann@example.com") }

      it "is false, with value_not_unique from the database and no column" do
        expect(model_record.load).to be(false)
        expect(model_record.errors.values).to match(
          [a_hash_including(origin: :database, code: :value_not_unique, target_column_name: nil)]
        )
      end

      it "gives the error of the catalog, with the text of the database as native_message" do
        model_record.load

        entry = model_record.errors[nil]

        expect(entry).to eq(
          catalog_error(
            :value_not_unique, target_column_name: nil, origin: :database, value: nil,
            native_message: entry[:details][:native_message]
          )
        )
        expect(entry[:details][:native_message]).to include("duplicate key value violates unique constraint")
      end

      it "leaves the table as it was" do
        model_record.load

        expect(AdapterSpecModels::Account.count).to eq(1)
      end
    end

    context "when a required column is empty" do
      let(:attributes) { {"email" => nil} }

      it "is false, with value_missing from the database and no column" do
        expect(model_record.load).to be(false)
        expect(model_record.errors.values).to match(
          [a_hash_including(origin: :database, code: :value_missing, target_column_name: nil)]
        )
      end
    end

    context "when the parent row does not exist" do
      let(:attributes) { {"email" => "ann@example.com", "company_id" => 999_999} }

      it "is false, with parent_missing from the database and no column" do
        expect(model_record.load).to be(false)
        expect(model_record.errors.values).to match(
          [a_hash_including(origin: :database, code: :parent_missing, target_column_name: nil)]
        )
      end
    end

    context "when a callback of the model stops the save" do
      let(:attributes) { {"email" => "ann@example.com", "nickname" => "halt"} }

      it "is false, with value_invalid from the model" do
        expect(model_record.load).to be(false)
        expect(model_record.errors.values).to match([a_hash_including(origin: :model, code: :value_invalid, target_column_name: nil)])
      end
    end

    context "when the database says a text is too long" do
      before do
        allow(model_record.record).to receive(:save!).and_raise(ActiveRecord::ValueTooLong.new("value too long"))
      end

      it "reports value_too_long" do
        model_record.load

        expect(model_record.errors.values).to match([a_hash_including(code: :value_too_long, target_column_name: nil)])
      end
    end

    context "when the database says a number is out of range" do
      before do
        allow(model_record.record).to receive(:save!).and_raise(ActiveRecord::RangeError.new("out of range"))
      end

      it "reports value_out_of_range" do
        model_record.load

        expect(model_record.errors.values).to match([a_hash_including(code: :value_out_of_range)])
      end
    end

    context "when the database refuses the row for another reason" do
      before do
        allow(model_record.record).to receive(:save!).and_raise(ActiveRecord::StatementInvalid.new("disk is full"))
      end

      it "reports database_error with the native message" do
        model_record.load

        expect(model_record.errors[nil]).to eq(
          catalog_error(
            :database_error, target_column_name: nil, origin: :database, value: nil, native_message: "disk is full"
          )
        )
      end
    end

    context "when it is called again after a refusal" do
      it "reports the last call only" do
        AdapterSpecModels::Account.create!(email: "ann@example.com")
        model_record.load
        model_record.record.email = "bob@example.com"
        model_record.load

        expect(model_record.errors.values).to eq([])
      end
    end

    context "inside an open transaction" do
      it "undoes only the refused row, and keeps the rows saved before it" do
        AdapterSpecModels::Account.create!(email: "ann@example.com")
        refused = target.build_record(attributes: {"email" => "ann@example.com"})
        accepted = target.build_record(attributes: {"email" => "bob@example.com"})

        AdapterSpecModels::Account.transaction do
          accepted.load
          refused.load

          expect(AdapterSpecModels::Account.pluck(:email)).to contain_exactly("ann@example.com", "bob@example.com")
          raise ActiveRecord::Rollback
        end
      end
    end
  end
end
