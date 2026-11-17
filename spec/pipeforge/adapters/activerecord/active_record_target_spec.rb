# frozen_string_literal: true

RSpec.describe Pipeforge::ActiveRecordTarget do
  subject(:target) { described_class.new(target_model_name: target_model_name) }

  let(:target_model_name) { "AdapterSpecModels::Membership" }
  # The model class, for the examples that read or write its rows.
  let(:model) { target_model_name.constantize }

  # The column of the schema with that name.
  def column_named(schema, name)
    schema.columns.find { |target_column| target_column.name == name }
  end

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

  describe "#enum_labels" do
    it "gives the labels of an enum stored as a number" do
      expect(described_class.new(target_model_name: "AdapterSpecModels::Shipment").enum_labels(column_name: "status")).to eq(%w[draft placed shipped])
    end

    it "gives the labels of an enum stored as text, not the values stored for them" do
      expect(described_class.new(target_model_name: "AdapterSpecModels::Shipment").enum_labels(column_name: "kind")).to eq(%w[retail wholesale])
    end

    it "gives nil for a column that is not an enum" do
      expect(described_class.new(target_model_name: "AdapterSpecModels::Shipment").enum_labels(column_name: "note")).to be_nil
    end
  end

  describe ".new" do
    it "builds the target of a model that uses another database" do
      expect(described_class.new(target_model_name: "AdapterSpecModels::Reading")).to be_a(described_class)
    end

    it "stops with target_table_not_found when the table of the model does not exist" do
      expect { described_class.new(target_model_name: "AdapterSpecModels::Ghost") }.to raise_error(Pipeforge::TargetSchemaError) do |error|
        expect(error.codes).to eq([:target_table_not_found])
      end
    end

    it "stops with active_record_model_not_found when no loaded model has the name" do
      expect { described_class.new(target_model_name: "AdapterSpecModels::Nowhere") }.to raise_error(Pipeforge::TargetSchemaError) do |error|
        expect(error.codes).to eq([:active_record_model_not_found])
      end
    end
  end

  describe "#schema" do
    subject(:schema) { target.schema }

    let(:target_model_name) { "AdapterSpecModels::User" }

    it "names the table and the model" do
      expect(schema).to have_attributes(table_name: "users", model_name: "AdapterSpecModels::User")
    end

    it "lists the columns that can be given a source column, in table order" do
      expect(schema.columns.map(&:name)).to eq(
        %w[email age balance bio active company_id created_at updated_at]
      )
    end

    it "gives the character limit of a string column as max_length" do
      expect(column_named(schema, "email")).to have_attributes(
        type: "string", sql_type: "character varying(255)", max_length: 255, limit: nil
      )
    end

    it "gives the size in bytes of an integer column as limit" do
      expect(column_named(schema, "age")).to have_attributes(type: "integer", limit: 2, max_length: nil)
    end

    context "with a bigint column and an integer column declared with no size" do
      let(:target_model_name) { "AdapterSpecModels::Quantity" }

      it "gives 8 bytes as the limit of the bigint column" do
        expect(column_named(schema, "big_count")).to have_attributes(type: "integer", limit: 8)
      end

      it "gives 4 bytes as the limit of the integer column, the size of its integer type" do
        expect(column_named(schema, "plain_count")).to have_attributes(type: "integer", limit: 4)
      end
    end

    it "reports an integer column as signed" do
      expect(column_named(schema, "age")).to have_attributes(is_signed: true)
    end

    it "reports a column that is not an integer as having no sign" do
      expect(column_named(schema, "email")).to have_attributes(is_signed: nil)
    end

    context "with an attribute of ActiveRecord's unsigned integer type" do
      let(:target_model_name) { "AdapterSpecModels::Counter" }

      it "reports that column as not signed, with its size" do
        expect(column_named(schema, "hits")).to have_attributes(type: "integer", limit: 2, is_signed: false)
      end

      it "reports the other integer column of the table as signed" do
        expect(column_named(schema, "misses")).to have_attributes(type: "integer", limit: 2, is_signed: true)
      end
    end

    context "with float columns" do
      let(:target_model_name) { "AdapterSpecModels::Measurement" }

      it "gives 24 as the limit of a single precision float" do
        expect(column_named(schema, "ratio")).to have_attributes(type: "float", limit: 24)
      end

      it "gives no limit for a float with no size, which is double precision" do
        expect(column_named(schema, "weight")).to have_attributes(type: "float", limit: nil)
      end
    end

    it "gives the precision and scale of a decimal column" do
      expect(column_named(schema, "balance")).to have_attributes(type: "decimal", precision: 10, scale: 2)
    end

    it "reports a text column with no limit" do
      expect(column_named(schema, "bio")).to have_attributes(type: "text", max_length: nil, limit: nil)
    end

    it "gives the default of a column" do
      expect(column_named(schema, "active").default).not_to be_nil
    end

    it "leaves out the primary key, which the database fills" do
      expect(column_named(schema, "id")).to be_nil
    end

    it "leaves out a column the model ignores" do
      expect(column_named(schema, "legacy_code")).to be_nil
    end

    it "leaves out a generated column" do
      expect(column_named(schema, "shout")).to be_nil
    end

    context "when the table has array columns" do
      let(:target_model_name) { "AdapterSpecModels::Playlist" }

      it "lists only the column that is not an array" do
        expect(schema.columns.map(&:name)).to eq(%w[title])
      end
    end

    it "offers the timestamps for mapping" do
      expect(schema.columns.select { |target_column| target_column.name.end_with?("_at") }).to all(have_attributes(type: "datetime"))
    end

    it "describes a foreign key with its association and parent table" do
      expect(column_named(schema, "company_id").foreign_key).to eq(
        Pipeforge::ForeignKey.new(association_name: "company", parent_table_name: "companies")
      )
    end

    it "gives no foreign key for a column that is not one" do
      expect(column_named(schema, "email").foreign_key).to be_nil
    end

    context "with a column the model declares with another type than the table" do
      let(:target_model_name) { "AdapterSpecModels::Ticket" }

      it "gives the type the model declares" do
        expect(column_named(schema, "rank")).to have_attributes(type: "integer", sql_type: "character varying")
      end

      it "gives no limit, because the model declares the integer with no size" do
        expect(column_named(schema, "rank").limit).to be_nil
      end
    end

    context "with enum columns and a default set only in the model" do
      let(:target_model_name) { "AdapterSpecModels::Shipment" }

      it "gives the labels of an enum stored as a number" do
        expect(column_named(schema, "status").enum_labels).to eq(%w[draft placed shipped])
      end

      it "gives the labels of an enum stored as text" do
        expect(column_named(schema, "kind").enum_labels).to eq(%w[retail wholesale])
      end

      it "gives no enum labels for a column that is not an enum" do
        expect(column_named(schema, "note").enum_labels).to be_nil
      end

      it "gives the default as the model sees it, which is the label for an enum" do
        expect(column_named(schema, "status").default).to eq("draft")
      end

      it "gives a default that only the model sets" do
        expect(column_named(schema, "channel").default).to eq("web")
      end

      it "requires a NOT NULL enum that has no default" do
        expect(column_named(schema, "priority").required).to be(true)
      end

      it "does not require a NOT NULL column whose default only the model sets" do
        expect(column_named(schema, "channel").required).to be(false)
      end

      it "does not require an enum that has a default" do
        expect(column_named(schema, "status").required).to be(false)
      end
    end

    context "with a model that does not record timestamps" do
      let(:target_model_name) { "AdapterSpecModels::Receipt" }

      it "requires the NOT NULL timestamps, because nothing fills them" do
        expect(schema.columns.select(&:required).map(&:name)).to eq(%w[number created_at updated_at])
      end
    end

    describe "which columns are required" do
      def required_names(schema)
        schema.columns.select(&:required).map(&:name)
      end

      it "requires a column that refuses an empty value and has no default" do
        expect(required_names(schema)).to eq(%w[email])
      end

      it "does not require the timestamps of a model that records them, because the model fills them" do
        expect(column_named(schema, "created_at")).to have_attributes(required: false)
        expect(column_named(schema, "updated_at")).to have_attributes(required: false)
      end

      it "does not require a column that accepts an empty value" do
        expect(column_named(schema, "age").required).to be(false)
      end

      it "does not require a nullable foreign key" do
        expect(column_named(schema, "company_id").required).to be(false)
      end

      context "with NOT NULL columns, with and without a default" do
        let(:target_model_name) { "AdapterSpecModels::Invoice" }

        it "does not require the one with a default" do
          expect(column_named(schema, "status").required).to be(false)
        end

        it "requires the one without" do
          expect(column_named(schema, "number").required).to be(true)
        end

        it "does not require the one whose default is a function of the database" do
          expect(column_named(schema, "issued_at").required).to be(false)
        end

        it "requires a NOT NULL foreign key even when the model marks its association optional" do
          expect(column_named(schema, "company_id").required).to be(true)
        end
      end
    end

    context "with a polymorphic association" do
      let(:target_model_name) { "AdapterSpecModels::Comment" }

      it "does not describe its column as a foreign key" do
        expect(column_named(schema, "commentable_id").foreign_key).to be_nil
      end
    end

    context "with a composite foreign key" do
      let(:target_model_name) { "AdapterSpecModels::OrderLine" }

      it "does not describe its columns as foreign keys" do
        expect(schema.columns.map(&:foreign_key)).to all(be_nil)
      end
    end

    context "with a composite primary key" do
      let(:target_model_name) { "AdapterSpecModels::Order" }

      it "leaves out every column of the key" do
        expect(schema.columns).to be_empty
      end
    end

    context "when the model is a subclass under single table inheritance" do
      let(:target_model_name) { "AdapterSpecModels::Car" }

      it "reads the model named, with the table it shares with its base class" do
        expect(schema).to have_attributes(table_name: "vehicles", model_name: "AdapterSpecModels::Car")
      end
    end

    context "when two unrelated models share one table" do
      let(:target_model_name) { "AdapterSpecModels::Note" }

      it "reads the model named, and not the other one" do
        expect(schema).to have_attributes(table_name: "notes", model_name: "AdapterSpecModels::Note")
      end
    end

    context "when the table of the model does not exist" do
      let(:target_model_name) { "AdapterSpecModels::Ghost" }

      it "stops with target_table_not_found and the table of the model" do
        expect { schema }.to raise_error(Pipeforge::TargetSchemaError) do |error|
          expect(error.errors.first).to include(code: :target_table_not_found, table_name: "ghosts")
        end
      end
    end

    context "when the model uses another database and its table is there" do
      let(:target_model_name) { "AdapterSpecModels::Reading" }

      it "reads the table in the database of the model" do
        expect(schema).to have_attributes(table_name: "readings", model_name: "AdapterSpecModels::Reading")
        expect(schema.columns.map(&:name)).to eq(%w[label])
      end
    end

    context "when the model uses another database and its table is only in the default database" do
      let(:target_model_name) { "AdapterSpecModels::UserInSecondaryDatabase" }

      it "stops with target_table_not_found and the table of the model" do
        expect { schema }.to raise_error(Pipeforge::TargetSchemaError) do |error|
          expect(error.errors.first).to include(code: :target_table_not_found, table_name: "users")
        end
      end
    end

    context "when no loaded model has the name" do
      let(:target_model_name) { "AdapterSpecModels::Nowhere" }

      it "stops with active_record_model_not_found and the name" do
        expect { schema }.to raise_error(Pipeforge::TargetSchemaError) do |error|
          expect(error.errors.first).to include(code: :active_record_model_not_found, model_name: "AdapterSpecModels::Nowhere")
        end
      end
    end

    context "when the model named is an abstract class" do
      let(:target_model_name) { "AdapterSpecModels::AbstractRecord" }

      it "stops with active_record_model_not_found and the name" do
        expect { schema }.to raise_error(Pipeforge::TargetSchemaError) do |error|
          expect(error.errors.first).to include(code: :active_record_model_not_found, model_name: "AdapterSpecModels::AbstractRecord")
        end
      end
    end

    it "reads no row of the table, only its structure" do
      statement_names = []
      subscription = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        statement_names << payload[:name]
      end

      described_class.new(target_model_name: "AdapterSpecModels::User").schema
      ActiveSupport::Notifications.unsubscribe(subscription)

      expect(statement_names.uniq).to eq(["SCHEMA"])
    end
  end

  describe "#build_record" do
    subject(:model_record) { target.build_record(attributes: attributes) }

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

    context "with the stored value of an enum label, written as text" do
      let(:attributes) { {"tier" => "1"} }

      it "leaves the enum out of the record, for the record to report" do
        expect(model_record.record.tier).to be_nil
      end

      it "reports it as value_not_allowed" do
        model_record.valid?

        expect(model_record.errors).to include(include(code: :value_not_allowed, target_column_name: "tier"))
      end
    end

    context "with the stored value of an enum label, as a number" do
      let(:attributes) { {"tier" => 0} }

      it "leaves the enum out of the record, for the record to report" do
        expect(model_record.record.tier).to be_nil
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
      let(:target_model_name) { "AdapterSpecModels::Shipment" }
      let(:attributes) { {"kind" => "wholesale"} }

      it "sets the label" do
        expect(model_record.record.kind).to eq("wholesale")
      end
    end

    context "with a json column" do
      let(:target_model_name) { "AdapterSpecModels::Profile" }
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

    context "with a jsonb column" do
      let(:target_model_name) { "AdapterSpecModels::Profile" }
      let(:attributes) { {"name" => "ann", "extras" => '{"beta":true}'} }

      it "holds the object the text describes" do
        expect(model_record.record.extras).to eq("beta" => true)
      end
    end
  end

  describe "#cast_value" do
    # What the adapter answers for a value.
    def cast_result(column_name, value)
      target.cast_value(column_name: column_name, value: value)
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

    it "gives the value of an enum column as it is, a stored value written as text included" do
      expect(cast("tier", "1")).to eq("1")
    end

    it "does not turn the stored value of an enum label, as a number, into the label" do
      expect(cast_result("tier", 1)).to eq(Pipeforge::CastResult.new(castable: true, cast_value: 1, json_value: 1))
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
        let(:target_model_name) { "AdapterSpecModels::User" }

        it "is true for a text that is read as true" do
          expect(cast_result("active", "yes").json_value).to be(true)
        end
      end

      context "with a date column" do
        let(:target_model_name) { "AdapterSpecModels::Event" }

        it "is the date written as year, month and day" do
          expect(cast_result("starts_on", "2024-2-3").json_value).to eq("2024-02-03")
        end

        it "is the time of a datetime with its offset and milliseconds" do
          expect(cast_result("starts_at", "2024-02-03 10:00:00 +0530").json_value).to eq("2024-02-03T10:00:00.000+05:30")
        end
      end
    end

    context "with a date column" do
      let(:target_model_name) { "AdapterSpecModels::Event" }

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
      let(:target_model_name) { "AdapterSpecModels::Event" }

      it "reads a space before the zone offset" do
        expect(cast("starts_at", "2024-02-03 10:00:00 +0530")).to be_a(Time)
      end

      it "says it cannot cast a text the model cannot cast" do
        expect(cast_result("starts_at", "garbage")).to eq(Pipeforge::CastResult::NOT_CASTABLE)
      end
    end

    context "with a json column" do
      let(:target_model_name) { "AdapterSpecModels::Profile" }

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

    context "with a jsonb column" do
      let(:target_model_name) { "AdapterSpecModels::Profile" }

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
        let(:target_model_name) { "AdapterSpecModels::User" }

        it "gives false for false" do
          expect(cast_result("active", false)).to eq(Pipeforge::CastResult.new(castable: true, cast_value: false, json_value: false))
        end
      end

      context "and a json column" do
        let(:target_model_name) { "AdapterSpecModels::Profile" }

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
        target.build_record(attributes: {"email" => "x@example.com", "tier" => "basic", "company_id" => company_id})
      end
    end

    it "loads the parents of all the records with one query" do
      model_records
      company
      other_company

      expect(queries_on("companies") { target.preload_parents(records: model_records) }.size).to eq(1)
    end

    it "makes the validation of the records run no query on the parent table" do
      model_records
      target.preload_parents(records: model_records)

      expect(queries_on("companies") { model_records.each(&:valid?) }).to eq([])
    end

    it "keeps a record whose parent does not exist invalid" do
      target.preload_parents(records: model_records)

      expect(model_records.map(&:valid?)).to eq([true, true, true, false])
    end

    context "with no records" do
      it "runs no query" do
        expect(queries_on("companies") { target.preload_parents(records: []) }).to eq([])
      end
    end

    context "with a polymorphic association" do
      let(:target_model_name) { "AdapterSpecModels::Comment" }

      it "leaves it alone" do
        records = [target.build_record(attributes: {"commentable_id" => 1, "commentable_type" => "Post"})]

        expect { target.preload_parents(records: records) }.not_to raise_error
      end
    end

    context "with a composite foreign key" do
      let(:target_model_name) { "AdapterSpecModels::OrderLine" }

      it "leaves it alone" do
        records = [target.build_record(attributes: {"shop_id" => 1, "order_number" => 2})]

        expect { target.preload_parents(records: records) }.not_to raise_error
      end
    end

    context "with a model that has no parent" do
      let(:target_model_name) { "AdapterSpecModels::Shipment" }

      it "does nothing" do
        records = [target.build_record(attributes: {"note" => "x"})]

        expect { target.preload_parents(records: records) }.not_to raise_error
      end
    end
  end

  describe "#transaction" do
    let(:target_model_name) { "AdapterSpecModels::Account" }

    def save_account(email:)
      model.create!(email: email)
    end

    context "without rollback_at_end" do
      it "keeps what the block wrote" do
        target.transaction(rollback_at_end: false) { save_account(email: "ann@example.com") }

        expect(model.count).to eq(1)
      end

      it "gives the result of the block" do
        expect(target.transaction(rollback_at_end: false) { :done }).to eq(:done)
      end

      it "undoes what the block wrote when the block raises, and raises the error" do
        expect do
          target.transaction(rollback_at_end: false) do
            save_account(email: "ann@example.com")
            raise "stop"
          end
        end.to raise_error(RuntimeError, "stop")

        expect(model.count).to eq(0)
      end
    end

    context "with rollback_at_end" do
      it "undoes what the block wrote" do
        target.transaction(rollback_at_end: true) { save_account(email: "ann@example.com") }

        expect(model.count).to eq(0)
      end

      it "gives the result of the block although the transaction was undone" do
        expect(target.transaction(rollback_at_end: true) { :done }).to eq(:done)
      end

      it "lets a row saved in it see the rows saved before it" do
        seen = nil
        target.transaction(rollback_at_end: true) do
          save_account(email: "ann@example.com")
          seen = model.pluck(:email)
        end

        expect(seen).to eq(["ann@example.com"])
      end
    end
  end

  describe "the engine's target class" do
    it "is this class, once the gem is loaded" do
      expect(Pipeforge::Engine.target_class).to be(described_class)
    end
  end
end
