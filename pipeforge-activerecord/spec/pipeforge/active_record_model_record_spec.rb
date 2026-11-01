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

        expect(model_record.errors).to contain_exactly(include(code: :value_invalid, target_column: "seats"))
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
        expect(model_record.errors).to contain_exactly(include(code: :value_not_allowed, target_column: "tier"))
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
end
