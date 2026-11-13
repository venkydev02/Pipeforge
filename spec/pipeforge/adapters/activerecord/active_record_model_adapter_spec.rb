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

    context "with a json column" do
      let(:model) { AdapterSpecModels::Profile }
      let(:attributes) { {"name" => "ann", "settings" => settings_text} }
      let(:settings_text) { '{"theme":"dark","size":3}' }

      it "holds the object the text describes" do
        expect(model_record.record.settings).to eq("theme" => "dark", "size" => 3)
      end

      context "and the text is a list" do
        let(:settings_text) { "[1,2]" }

        it "holds the list" do
          expect(model_record.record.settings).to eq([1, 2])
        end
      end

      context "and the text is a JSON string written with its quotes" do
        let(:settings_text) { '"hello"' }

        it "holds that string" do
          expect(model_record.record.settings).to eq("hello")
        end
      end

      context "and the text is not JSON" do
        let(:settings_text) { "{oops" }

        it "holds nothing" do
          expect(model_record.record.settings).to be_nil
        end

        it "keeps the text, as given, for the record to report" do
          expect(model_record.attributes["settings"]).to eq("{oops")
        end
      end

      context "and the text is the JSON null" do
        let(:settings_text) { "null" }

        it "holds nothing" do
          expect(model_record.record.settings).to be_nil
        end

        it "leaves nothing for the record to report" do
          expect(model_record.valid?).to be(true)
        end
      end

      context "and the value is empty" do
        let(:settings_text) { nil }

        it "holds nothing" do
          expect(model_record.record.settings).to be_nil
        end
      end

      context "and the value is already an object" do
        let(:settings_text) { {"theme" => "dark"} }

        it "keeps the object" do
          expect(model_record.record.settings).to eq("theme" => "dark")
        end
      end
    end

    context "with a jsonb column", :postgresql_only do
      let(:model) { AdapterSpecModels::Profile }
      let(:attributes) { {"name" => "ann", "extras" => '{"beta":true}'} }

      it "holds the object the text describes" do
        expect(model_record.record.extras).to eq("beta" => true)
      end
    end
  end

  describe "#cast_value" do
    # What the adapter answers for a value.
    def cast_result(column_name, value)
      model_adapter.cast_value(column_name: column_name, value: value)
    end

    # The cast value of a value the adapter can cast.
    def cast(column_name, value)
      cast_result(column_name, value).cast_value
    end

    it "says it can cast a text and gives the number the model would load, for an integer column" do
      expect(cast_result("seats", "12")).to eq(Pipeforge::CastResult.new(castable: true, cast_value: 12, json_value: 12))
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

    context "with the json value" do
      it "is the number for a text in an integer column" do
        expect(cast_result("seats", "12").json_value).to eq(12)
      end

      it "is the cast number for a text that is not a number" do
        expect(cast_result("seats", "abc").json_value).to eq(0)
      end

      it "is the label for the label of an enum" do
        expect(cast_result("tier", "pro").json_value).to eq("pro")
      end

      it "is the text itself for a string column" do
        expect(cast_result("email", "ann@example.com").json_value).to eq("ann@example.com")
      end

      it "is the label for an enum label the model does not know" do
        expect(cast_result("tier", "nope")).to eq(Pipeforge::CastResult.new(castable: true, cast_value: "nope", json_value: "nope"))
      end

      it "is the cast number for a number outside the range of its column" do
        expect(cast_result("seats", "99999")).to eq(Pipeforge::CastResult.new(castable: true, cast_value: 99_999, json_value: 99_999))
      end

      it "is the number rounded to the scale, written as a text, for a decimal column" do
        expect(cast_result("fee", "12.345").json_value).to eq("12.35")
      end

      context "with a boolean column" do
        let(:model) { AdapterSpecModels::User }

        it "is true for a text that is read as true" do
          expect(cast_result("active", "yes").json_value).to be(true)
        end
      end

      context "with a date column" do
        let(:model) { AdapterSpecModels::Event }

        it "is the date written as year, month and day" do
          expect(cast_result("starts_on", "2024-2-3").json_value).to eq("2024-02-03")
        end

        it "is the time of a datetime with its offset and milliseconds" do
          expect(cast_result("starts_at", "2024-02-03 10:00:00 +0530").json_value).to eq("2024-02-03T10:00:00.000+05:30")
        end
      end
    end

    context "with a date column" do
      let(:model) { AdapterSpecModels::Event }

      it "reads the formats the model reads" do
        expect(cast("starts_on", "2024-2-3")).to eq(Date.new(2024, 2, 3))
        expect(cast("starts_on", "Feb 3, 2024")).to eq(Date.new(2024, 2, 3))
        expect(cast("starts_on", "20240203")).to eq(Date.new(2024, 2, 3))
      end

      it "says it cannot cast a text the model cannot cast" do
        expect(cast_result("starts_on", "garbage")).to eq(Pipeforge::CastResult::NOT_CASTABLE)
      end

      it "says it cannot cast a day that is not in the calendar" do
        expect(cast_result("starts_on", "2024-02-30")).to eq(Pipeforge::CastResult::NOT_CASTABLE)
      end
    end

    context "with a datetime column" do
      let(:model) { AdapterSpecModels::Event }

      it "reads a space before the zone offset" do
        expect(cast("starts_at", "2024-02-03 10:00:00 +0530")).to be_a(Time)
      end

      it "says it cannot cast a text the model cannot cast" do
        expect(cast_result("starts_at", "garbage")).to eq(Pipeforge::CastResult::NOT_CASTABLE)
      end
    end

    context "with a json column" do
      let(:model) { AdapterSpecModels::Profile }

      it "gives the object that a text describes" do
        expect(cast("settings", '{"theme":"dark","size":3}')).to eq("theme" => "dark", "size" => 3)
      end

      it "gives the list that a text describes" do
        expect(cast("settings", "[1,2]")).to eq([1, 2])
      end

      it "gives the string for a JSON string written with its quotes" do
        expect(cast("settings", '"hello"')).to eq("hello")
      end

      it "says it cannot cast a text that is not JSON" do
        expect(cast_result("settings", "{oops")).to eq(Pipeforge::CastResult::NOT_CASTABLE)
      end

      it "says it can cast the JSON null, with nothing to load" do
        expect(cast_result("settings", "null")).to eq(Pipeforge::CastResult.new(castable: true, cast_value: nil, json_value: nil))
      end

      it "gives the object the text describes as the json value" do
        expect(cast_result("settings", '{"a": 1}').json_value).to eq("a" => 1)
      end
    end

    context "with a jsonb column", :postgresql_only do
      let(:model) { AdapterSpecModels::Profile }

      it "gives the object that a text describes" do
        expect(cast("extras", '{"beta":true}')).to eq("beta" => true)
      end
    end

    context "with a value that is not a text, as a value mapping gives it" do
      it "gives the number for a number in an integer column" do
        expect(cast_result("seats", 12)).to eq(Pipeforge::CastResult.new(castable: true, cast_value: 12, json_value: 12))
      end

      it "says it cannot cast nil" do
        expect(cast_result("seats", nil)).to eq(Pipeforge::CastResult::NOT_CASTABLE)
      end

      context "and a boolean column" do
        let(:model) { AdapterSpecModels::User }

        it "gives false for false" do
          expect(cast_result("active", false)).to eq(Pipeforge::CastResult.new(castable: true, cast_value: false, json_value: false))
        end
      end

      context "and a json column" do
        let(:model) { AdapterSpecModels::Profile }

        it "gives the Hash as it is" do
          expect(cast_result("settings", {"theme" => "dark"})).to eq(
            Pipeforge::CastResult.new(castable: true, cast_value: {"theme" => "dark"}, json_value: {"theme" => "dark"})
          )
        end

        it "gives the Array as it is" do
          expect(cast_result("settings", [{"theme" => "dark"}])).to eq(
            Pipeforge::CastResult.new(castable: true, cast_value: [{"theme" => "dark"}], json_value: [{"theme" => "dark"}])
          )
        end
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

  describe "#transaction" do
    let(:model) { AdapterSpecModels::Account }

    def save_account(email:)
      model.create!(email: email)
    end

    context "without rollback_at_end" do
      it "keeps what the block wrote" do
        model_adapter.transaction(rollback_at_end: false) { save_account(email: "ann@example.com") }

        expect(model.count).to eq(1)
      end

      it "gives the result of the block" do
        expect(model_adapter.transaction(rollback_at_end: false) { :done }).to eq(:done)
      end

      it "undoes what the block wrote when the block raises, and raises the error" do
        expect do
          model_adapter.transaction(rollback_at_end: false) do
            save_account(email: "ann@example.com")
            raise "stop"
          end
        end.to raise_error(RuntimeError, "stop")

        expect(model.count).to eq(0)
      end
    end

    context "with rollback_at_end" do
      it "undoes what the block wrote" do
        model_adapter.transaction(rollback_at_end: true) { save_account(email: "ann@example.com") }

        expect(model.count).to eq(0)
      end

      it "gives the result of the block although the transaction was undone" do
        expect(model_adapter.transaction(rollback_at_end: true) { :done }).to eq(:done)
      end

      it "lets a row saved in it see the rows saved before it" do
        seen = nil
        model_adapter.transaction(rollback_at_end: true) do
          save_account(email: "ann@example.com")
          seen = model.pluck(:email)
        end

        expect(seen).to eq(["ann@example.com"])
      end
    end
  end
end
