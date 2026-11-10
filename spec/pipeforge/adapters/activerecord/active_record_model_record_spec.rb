# frozen_string_literal: true

RSpec.describe Pipeforge::ActiveRecordModelRecord do
  subject(:model_record) { model_adapter.build_record(attributes: attributes) }

  let(:model_adapter) { Pipeforge::ActiveRecordModelAdapter.new(model: AdapterSpecModels::Membership) }
  let(:company) { AdapterSpecModels::Company.create!(name: "Acme") }
  let(:attributes) { {"email" => "ann@example.com", "tier" => "basic", "company_id" => company.id} }

  def codes_of(model_record)
    model_record.errors.map { |error| error[:code] }
  end

  describe "#record" do
    it "is the unsaved record" do
      expect(model_record.record).to be_a(AdapterSpecModels::Membership).and have_attributes(new_record?: true)
    end
  end

  describe "#errors" do
    it "is empty before the record is validated" do
      expect(model_record.errors).to eq([])
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

      it "includes the label as it was given, because the record could not hold it" do
        expect(model_record.attributes["tier"]).to eq("gold")
      end
    end
  end

  describe "#valid?" do
    context "when the model finds no mistake" do
      it "is true, with no errors" do
        expect(model_record.valid?).to be(true)
        expect(model_record.errors).to eq([])
      end
    end

    context "when a required value is blank" do
      let(:attributes) { {"email" => nil, "tier" => "basic", "company_id" => company.id} }

      it "is false, with value_missing for that column" do
        expect(model_record.valid?).to be(false)
        expect(model_record.errors).to contain_exactly(include(code: :value_missing, target_column: "email"))
      end

      it "gives a message that a person can read" do
        model_record.valid?

        expect(model_record.errors.first[:message]).to include("Email")
      end
    end

    context "when a value is too long" do
      let(:attributes) { {"email" => "a-very-long-address@example.com", "tier" => "basic", "company_id" => company.id} }

      it "gives value_too_long for that column" do
        model_record.valid?

        expect(model_record.errors).to contain_exactly(include(code: :value_too_long, target_column: "email"))
      end
    end

    context "when a value is already taken by a row of the table" do
      before do
        AdapterSpecModels::Membership.create!(email: "ann@example.com", tier: :basic, company: company)
      end

      it "gives value_not_unique for that column" do
        model_record.valid?

        expect(model_record.errors).to contain_exactly(include(code: :value_not_unique, target_column: "email"))
      end
    end

    context "when the parent does not exist" do
      let(:attributes) { {"email" => "ann@example.com", "tier" => "basic", "company_id" => 999_999} }

      it "gives parent_missing for the foreign key column" do
        model_record.valid?

        expect(model_record.errors).to contain_exactly(include(code: :parent_missing, target_column: "company_id"))
      end
    end

    context "when no parent is given" do
      let(:attributes) { {"email" => "ann@example.com", "tier" => "basic", "company_id" => nil} }

      it "gives value_missing for the foreign key column, because the value is empty" do
        model_record.valid?

        expect(model_record.errors).to contain_exactly(include(code: :value_missing, target_column: "company_id"))
      end
    end

    context "when another validation fails" do
      let(:attributes) { {"email" => "ann@example.com", "tier" => "basic", "company_id" => company.id, "seats" => 200_000} }

      it "gives value_invalid for that column" do
        model_record.valid?

        expect(model_record.errors).to contain_exactly(include(origin: :model, code: :value_invalid, target_column: "seats"))
      end
    end

    context "when the mistake is on the record as a whole" do
      let(:attributes) { {"email" => "closed@example.com", "tier" => "basic", "company_id" => company.id} }

      it "gives value_invalid with no column" do
        model_record.valid?

        expect(model_record.errors).to contain_exactly(include(code: :value_invalid, target_column: nil))
      end
    end

    context "when an enum label is not one the model knows" do
      let(:attributes) { {"email" => "ann@example.com", "tier" => "gold", "company_id" => company.id} }

      it "gives value_not_allowed for that column" do
        expect(model_record.valid?).to be(false)
        expect(model_record.errors).to contain_exactly(include(origin: :model, code: :value_not_allowed, target_column: "tier"))
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

        expect(model_record.errors.map { |error| [error[:target_column], error[:code]] }).to contain_exactly(
          ["tier", :value_not_allowed], ["email", :value_missing]
        )
      end
    end

    context "when it is called again" do
      it "reports the mistakes of the last call only" do
        model_record.valid?
        model_record.record.email = "ann@example.com"
        model_record.record.tier = :basic
        model_record.record.company = company
        model_record.valid?

        expect(model_record.errors).to eq([])
      end
    end
  end

  describe "#load" do
    subject(:model_record) { model_adapter.build_record(attributes: attributes) }

    let(:model_adapter) { Pipeforge::ActiveRecordModelAdapter.new(model: AdapterSpecModels::Account) }
    let(:attributes) { {"email" => "ann@example.com", "nickname" => "ann", "company_id" => company.id} }

    context "when the table takes the row" do
      it "is true, with no errors" do
        expect(model_record.load).to be(true)
        expect(model_record.errors).to eq([])
      end

      it "saves the record" do
        model_record.load

        expect(AdapterSpecModels::Account.where(email: "ann@example.com").count).to eq(1)
      end

      it "does not run the model's validations again" do
        validating_adapter = Pipeforge::ActiveRecordModelAdapter.new(model: AdapterSpecModels::Membership)
        record = validating_adapter.build_record(attributes: {"email" => nil, "tier" => "basic"})

        expect(record.load).to be(false)
        expect(record.errors.map { |error| error[:code] }).to eq([:value_missing])
        expect(record.record.errors).to be_empty
      end
    end

    context "when the table already has the value of a unique index" do
      before { AdapterSpecModels::Account.create!(email: "ann@example.com") }

      it "is false, with value_not_unique from the database and no column" do
        expect(model_record.load).to be(false)
        expect(model_record.errors).to match(
          [a_hash_including(origin: :database, code: :value_not_unique, target_column: nil)]
        )
      end

      it "keeps the native message" do
        model_record.load

        expect(model_record.errors.first[:message]).to include("UNIQUE constraint failed: accounts.email")
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
        expect(model_record.errors).to match(
          [a_hash_including(origin: :database, code: :value_missing, target_column: nil)]
        )
      end
    end

    context "when the parent row does not exist" do
      let(:attributes) { {"email" => "ann@example.com", "company_id" => 999_999} }

      it "is false, with parent_missing from the database and no column" do
        expect(model_record.load).to be(false)
        expect(model_record.errors).to match(
          [a_hash_including(origin: :database, code: :parent_missing, target_column: nil)]
        )
      end
    end

    context "when a callback of the model stops the save" do
      let(:attributes) { {"email" => "ann@example.com", "nickname" => "halt"} }

      it "is false, with value_invalid from the model" do
        expect(model_record.load).to be(false)
        expect(model_record.errors).to match([a_hash_including(origin: :model, code: :value_invalid, target_column: nil)])
      end
    end

    context "when the database says a text is too long" do
      before do
        allow(model_record.record).to receive(:save!).and_raise(ActiveRecord::ValueTooLong.new("value too long"))
      end

      it "reports value_too_long" do
        model_record.load

        expect(model_record.errors).to match([a_hash_including(code: :value_too_long, target_column: nil)])
      end
    end

    context "when the database says a number is out of range" do
      before do
        allow(model_record.record).to receive(:save!).and_raise(ActiveRecord::RangeError.new("out of range"))
      end

      it "reports value_out_of_range" do
        model_record.load

        expect(model_record.errors).to match([a_hash_including(code: :value_out_of_range)])
      end
    end

    context "when a number is outside the range of the type of its column" do
      let(:model_adapter) { Pipeforge::ActiveRecordModelAdapter.new(model: AdapterSpecModels::Membership) }
      let(:attributes) { {"email" => "ann@example.com", "tier" => "basic", "seats" => 40_000, "company_id" => company.id} }

      it "does not write the row" do
        expect(model_record.load).to be(false)
      end

      it "reports value_out_of_range as a refusal of the model" do
        model_record.load

        expect(model_record.errors).to match([a_hash_including(origin: :model, code: :value_out_of_range, target_column: nil)])
      end
    end

    context "when the database refuses the row for another reason" do
      before do
        allow(model_record.record).to receive(:save!).and_raise(ActiveRecord::StatementInvalid.new("disk is full"))
      end

      it "reports database_error with the native message" do
        model_record.load

        expect(model_record.errors).to match([a_hash_including(code: :database_error, message: "disk is full")])
      end
    end

    context "when it is called again after a refusal" do
      it "reports the last call only" do
        AdapterSpecModels::Account.create!(email: "ann@example.com")
        model_record.load
        model_record.record.email = "bob@example.com"
        model_record.load

        expect(model_record.errors).to eq([])
      end
    end

    context "inside an open transaction" do
      it "undoes only the refused row, and keeps the rows saved before it" do
        AdapterSpecModels::Account.create!(email: "ann@example.com")
        refused = model_adapter.build_record(attributes: {"email" => "ann@example.com"})
        accepted = model_adapter.build_record(attributes: {"email" => "bob@example.com"})

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
