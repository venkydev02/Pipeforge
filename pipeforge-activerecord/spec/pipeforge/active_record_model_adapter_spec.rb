# frozen_string_literal: true

RSpec.describe Pipeforge::ActiveRecordModelAdapter do
  subject(:model_adapter) { described_class.new(model: model) }

  let(:model) { AdapterSpecModels::Membership }

  # The SQL statements that the block runs against the given table, not counting schema reads.
  def queries_on(table, &block)
    statements = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, _start, _finish, _id, payload|
      statements << payload[:sql] if payload[:name] != "SCHEMA" && payload[:sql].include?(%("#{table}"))
    end
    block.call

    statements
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  describe "#build_record" do
    subject(:model_record) { model_adapter.build_record(attributes: attributes) }

    let(:attributes) { {"email" => "ann@example.com", "seats" => "12", "tier" => nil} }

    it "returns the record wrapped for the run" do
      expect(model_record).to be_a(Pipeforge::ActiveRecordModelRecord)
    end

    it "builds an unsaved record of the model from the attributes" do
      expect(model_record.record).to have_attributes(new_record?: true, email: "ann@example.com", seats: 12, tier: nil)
    end

    it "does not touch the database" do
      expect(queries_on("memberships") { model_record }).to eq([])
    end

    context "with an enum label" do
      let(:attributes) { {"tier" => "pro"} }

      it "sets the enum" do
        expect(model_record.record.tier).to eq("pro")
      end
    end

    context "with the stored value of an enum, written as text" do
      let(:attributes) { {"tier" => "1"} }

      it "casts it to the stored value" do
        expect(model_record.record.tier).to eq("pro")
      end
    end

    context "with the stored value of an enum, as a number" do
      let(:attributes) { {"tier" => 0} }

      it "sets the enum" do
        expect(model_record.record.tier).to eq("basic")
      end
    end

    context "with an enum label the model does not know" do
      let(:attributes) { {"email" => "ann@example.com", "tier" => "gold"} }

      it "builds the record without raising" do
        expect { model_record }.not_to raise_error
      end

      it "leaves the enum out of the record" do
        expect(model_record.record.tier).to be_nil
      end

      it "keeps the other attributes" do
        expect(model_record.record.email).to eq("ann@example.com")
      end
    end

    context "with an enum stored as text" do
      let(:model) { AdapterSpecModels::Shipment }
      let(:attributes) { {"kind" => "wholesale"} }

      it "sets the label" do
        expect(model_record.record.kind).to eq("wholesale")
      end
    end
  end

  describe "#cast_text" do
    def cast(column_name, text)
      model_adapter.cast_text(column_name: column_name, text: text)
    end

    it "gives the number the model would load for a text in an integer column" do
      expect(cast("seats", "12")).to eq(12)
    end

    it "gives the lenient cast of the model for a text that is not a number" do
      expect(cast("seats", "abc")).to eq(0)
    end

    it "rounds a decimal to the scale of its column" do
      expect(cast("fee", "999.999")).to eq(BigDecimal(1000))
    end

    it "gives the label of an enum for its label" do
      expect(cast("tier", "pro")).to eq("pro")
    end

    it "gives a text for a stored enum value written as text, which the checks then compare" do
      expect(cast("tier", "1")).to eq("1")
    end

    it "gives a text as it is for a string column" do
      expect(cast("email", "ann@example.com")).to eq("ann@example.com")
    end

    it "reads nothing from the table" do
      expect(queries_on("memberships") { cast("seats", "12") }).to eq([])
    end

    context "with a date column" do
      let(:model) { AdapterSpecModels::Event }

      it "reads the formats the model reads" do
        expect(cast("starts_on", "2024-2-3")).to eq(Date.new(2024, 2, 3))
        expect(cast("starts_on", "Feb 3, 2024")).to eq(Date.new(2024, 2, 3))
        expect(cast("starts_on", "20240203")).to eq(Date.new(2024, 2, 3))
      end

      it "gives nil for a text the model cannot read" do
        expect(cast("starts_on", "garbage")).to be_nil
      end

      it "gives nil for a day that is not in the calendar" do
        expect(cast("starts_on", "2024-02-30")).to be_nil
      end
    end

    context "with a datetime column" do
      let(:model) { AdapterSpecModels::Event }

      it "reads a space before the zone offset" do
        expect(cast("starts_at", "2024-02-03 10:00:00 +0530")).to be_a(Time)
      end

      it "gives nil for a text the model cannot read" do
        expect(cast("starts_at", "garbage")).to be_nil
      end
    end
  end

  describe "#preload_parents" do
    let(:company) { AdapterSpecModels::Company.create!(name: "Acme") }
    let(:other_company) { AdapterSpecModels::Company.create!(name: "Other") }
    let(:model_records) do
      [company.id, other_company.id, company.id, 999_999].map do |company_id|
        model_adapter.build_record(attributes: {"email" => "x@example.com", "tier" => "basic", "company_id" => company_id})
      end
    end

    it "loads the parents of all the records with one query" do
      model_records
      company
      other_company

      expect(queries_on("companies") { model_adapter.preload_parents(records: model_records) }.size).to eq(1)
    end

    it "makes the validation of the records run no query on the parent table" do
      model_records
      model_adapter.preload_parents(records: model_records)

      expect(queries_on("companies") { model_records.each(&:valid?) }).to eq([])
    end

    it "keeps a record whose parent does not exist invalid" do
      model_adapter.preload_parents(records: model_records)

      expect(model_records.map(&:valid?)).to eq([true, true, true, false])
    end

    context "with no records" do
      it "runs no query" do
        expect(queries_on("companies") { model_adapter.preload_parents(records: []) }).to eq([])
      end
    end

    context "with a polymorphic association" do
      let(:model) { AdapterSpecModels::Comment }

      it "leaves it alone" do
        records = [model_adapter.build_record(attributes: {"commentable_id" => 1, "commentable_type" => "Post"})]

        expect { model_adapter.preload_parents(records: records) }.not_to raise_error
      end
    end

    context "with a composite foreign key" do
      let(:model) { AdapterSpecModels::OrderLine }

      it "leaves it alone" do
        records = [model_adapter.build_record(attributes: {"shop_id" => 1, "order_number" => 2})]

        expect { model_adapter.preload_parents(records: records) }.not_to raise_error
      end
    end

    context "with a model that has no parent" do
      let(:model) { AdapterSpecModels::Shipment }

      it "does nothing" do
        records = [model_adapter.build_record(attributes: {"note" => "x"})]

        expect { model_adapter.preload_parents(records: records) }.not_to raise_error
      end
    end
  end
end
