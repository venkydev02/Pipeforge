# frozen_string_literal: true

# The target works on a model, and ActiveRecord is a third-party gem, so every example uses a real model over a real
# table of the PostgreSQL test database, made by define_model in the example and dropped after it, and nothing of
# ActiveRecord is replaced by a double: a change in a new version of ActiveRecord shows here. The models are named for
# the fact they show. The only models taken from spec/support/active_record_helper.rb are the parents
# AdapterSpecModels::Company and AdapterSpecModels::Order, AdapterSpecModels::Reading and
# AdapterSpecModels::UserInSecondaryDatabase (another database) and AdapterSpecModels::AbstractRecord. The one double
# is the ActiveRecordSchemaReader, which is ours and has its own spec, in the examples of #schema.
# An example that no break fails alone is kept for what the rule accepts or reports (contract only).
RSpec.describe Pipeforge::ActiveRecordTarget do
  subject(:target) { described_class.new(target_model_name: model.name) }

  # The error of the ErrorCatalog for a value the record could not be given.
  def catalog_error(key:, target_column_name:, value:)
    Pipeforge::ErrorCatalog::ERRORS.fetch(key).call(origin: :model, target_column_name: target_column_name, value: value)
  end

  def define_model_with_numbers
    define_model(
      name: "ModelWithNumbers",
      columns: lambda do |table|
        table.integer :seats, limit: 2
        table.decimal :fee, precision: 5, scale: 2
        table.string :email
      end
    )
  end

  def define_model_with_boolean
    define_model(name: "ModelWithBoolean", columns: ->(table) { table.boolean :active, default: true })
  end

  def define_model_with_dates
    define_model(
      name: "ModelWithDates",
      columns: lambda do |table|
        table.date :starts_on
        table.datetime :starts_at
      end
    )
  end

  def define_model_with_json
    define_model(
      name: "ModelWithJson",
      columns: lambda do |table|
        table.string :name
        table.json :settings
        table.jsonb :extras
      end
    )
  end

  def define_model_with_enum
    define_model(
      name: "ModelWithEnum",
      columns: lambda do |table|
        table.integer :tier
        table.string :kind
        table.string :note
      end
    ) do
      enum :tier, {basic: 0, pro: 1}
      enum :kind, {retail: "retail", wholesale: "wholesale"}
    end
  end

  def define_model_with_enum_and_date
    define_model(
      name: "ModelWithEnumAndDate",
      columns: lambda do |table|
        table.integer :tier
        table.date :starts_on
      end
    ) do
      enum :tier, {basic: 0, pro: 1}
    end
  end

  def define_model_with_polymorphic_parent
    define_model(
      name: "ModelWithPolymorphicParent",
      columns: lambda do |table|
        table.integer :commentable_id
        table.string :commentable_type
      end
    ) do
      belongs_to :commentable, polymorphic: true
    end
  end

  def define_model_with_parent
    define_model(name: "ModelWithParent", columns: ->(table) { table.bigint :company_id }) do
      belongs_to :company, class_name: "AdapterSpecModels::Company", optional: false
    end
  end

  def define_model_with_two_parents
    define_model(
      name: "ModelWithTwoParents",
      columns: lambda do |table|
        table.bigint :from_company_id
        table.bigint :to_company_id
      end
    ) do
      belongs_to :from_company, class_name: "AdapterSpecModels::Company"
      belongs_to :to_company, class_name: "AdapterSpecModels::Company"
    end
  end

  def define_model_with_composite_parent
    define_model(
      name: "ModelWithCompositeParent",
      columns: lambda do |table|
        table.integer :shop_id
        table.integer :order_number
      end
    ) do
      belongs_to :order, class_name: "AdapterSpecModels::Order",
        foreign_key: [:shop_id, :order_number], primary_key: [:shop_id, :number]
    end
  end

  def define_model_with_children
    define_model(name: "ModelWithParentId", columns: ->(table) { table.integer :parent_id })
    define_model(name: "ModelWithChildren", columns: ->(table) { table.string :name }) do
      has_many :children, class_name: "AdapterSpecModels::ModelWithParentId", foreign_key: :parent_id
    end
  end

  def define_model_without_parent
    define_model(name: "ModelWithoutParent", columns: ->(table) { table.string :name })
  end

  def define_model_with_email
    define_model(name: "ModelWithEmail", columns: ->(table) { table.string :email })
  end

  describe ".new" do
    subject(:target) { described_class.new(target_model_name: target_model_name) }

    context "when target_model_name is the name of a loaded model with a table" do
      let(:target_model_name) { define_model_with_numbers.name }

      # contract only
      it "builds the target" do
        expect(target).to be_a(described_class)
      end
    end

    context "when target_model_name is the name of no loaded model, only the beginning of the name of one" do
      let(:target_model_name) { define_model(name: "ModelWithLongerName").name.delete_suffix("Name") }

      it "raises TargetSchemaError with active_record_model_not_found, naming model_name" do
        expect { target }.to raise_error(Pipeforge::TargetSchemaError) do |error|
          expect(error.errors.first).to include(code: :active_record_model_not_found, model_name: "AdapterSpecModels::ModelWithLonger")
        end
      end
    end

    context "when target_model_name is the name of an abstract class" do
      let(:target_model_name) { "AdapterSpecModels::AbstractRecord" }

      it "raises TargetSchemaError with active_record_model_not_found" do
        expect { target }.to raise_error(Pipeforge::TargetSchemaError) do |error|
          expect(error.errors.first).to include(code: :active_record_model_not_found)
        end
      end
    end

    context "when target_model_name is ModelWithoutTable, a model whose table does not exist" do
      let(:target_model_name) { define_model(name: "ModelWithoutTable", table: false).name }

      it "raises TargetSchemaError with target_table_not_found, naming table_name" do
        expect { target }.to raise_error(Pipeforge::TargetSchemaError) do |error|
          expect(error.errors.first).to include(code: :target_table_not_found, table_name: "model_without_table")
        end
      end
    end

    context "when target_model_name is Reading, a model of another database whose table is there" do
      let(:target_model_name) { "AdapterSpecModels::Reading" }

      # contract only
      it "builds the target" do
        expect(target).to be_a(described_class)
      end
    end

    context "when target_model_name is UserInSecondaryDatabase, whose table is only in the default database" do
      let(:target_model_name) { "AdapterSpecModels::UserInSecondaryDatabase" }

      it "raises TargetSchemaError with target_table_not_found, naming table_name" do
        expect { target }.to raise_error(Pipeforge::TargetSchemaError) do |error|
          expect(error.errors.first).to include(code: :target_table_not_found, table_name: "users")
        end
      end
    end
  end

  describe "#enum_labels" do
    subject(:enum_labels) { target.enum_labels(column_name: column_name) }

    context "when model is ModelWithEnum" do
      let(:model) { define_model_with_enum }

      context "and column_name is tier, an enum stored as a number" do
        let(:column_name) { "tier" }

        it "answers the labels" do
          expect(enum_labels).to eq(%w[basic pro])
        end
      end

      context "and column_name is kind, an enum stored as text" do
        let(:column_name) { "kind" }

        # contract only
        it "answers the labels" do
          expect(enum_labels).to eq(%w[retail wholesale])
        end
      end

      context "and column_name is note, which is no enum" do
        let(:column_name) { "note" }

        # contract only
        it "answers nil" do
          expect(enum_labels).to be_nil
        end
      end

      context "and column_name is not a column of the table" do
        let(:column_name) { "nope" }

        # contract only
        it "answers nil" do
          expect(enum_labels).to be_nil
        end
      end
    end
  end

  describe "#schema" do
    subject(:schema) { target.schema }

    let(:schema_reader) { instance_double(Pipeforge::ActiveRecordSchemaReader, call: schema_from_reader) }
    let(:schema_from_reader) { Pipeforge::TargetSchema.new(table_name: "tables", model_name: "Model", columns: []) }

    before do
      allow(Pipeforge::ActiveRecordSchemaReader).to receive(:new).and_return(schema_reader)
    end

    context "when model is ModelWithEnum" do
      let(:model) { define_model_with_enum }

      it "builds the schema reader with the model, its enum_labels and no polymorphic_columns" do
        schema

        expect(Pipeforge::ActiveRecordSchemaReader).to have_received(:new).with(
          model: model,
          enum_labels: {"tier" => %w[basic pro], "kind" => %w[retail wholesale]},
          polymorphic_columns: {}
        )
      end

      # contract only
      it "answers what the schema reader answers" do
        expect(schema).to be(schema_from_reader)
      end
    end

    context "when model is ModelWithPolymorphicParent" do
      let(:model) { define_model_with_polymorphic_parent }

      it "gives the schema reader the id column and the type column of the association as polymorphic_columns" do
        schema

        expect(Pipeforge::ActiveRecordSchemaReader).to have_received(:new).with(
          model: model,
          enum_labels: {},
          polymorphic_columns: {
            "commentable_id" => Pipeforge::PolymorphicColumn.new(association_name: "commentable", role: "id"),
            "commentable_type" => Pipeforge::PolymorphicColumn.new(association_name: "commentable", role: "type")
          }
        )
      end
    end

    context "when model is ModelWithParent, whose belongs_to is not polymorphic" do
      let(:model) { define_model_with_parent }

      it "gives the schema reader no polymorphic_columns" do
        schema

        expect(Pipeforge::ActiveRecordSchemaReader).to have_received(:new).with(
          model: model, enum_labels: {}, polymorphic_columns: {}
        )
      end
    end

    context "when model is ModelWithoutParent, with no enum and no association" do
      let(:model) { define_model_without_parent }

      # contract only
      it "gives the schema reader no enum_labels and no polymorphic_columns" do
        schema

        expect(Pipeforge::ActiveRecordSchemaReader).to have_received(:new).with(
          model: model, enum_labels: {}, polymorphic_columns: {}
        )
      end
    end
  end

  describe "#build_record" do
    subject(:model_record) { target.build_record(attributes: attributes) }

    context "when model is ModelWithNumbers" do
      let(:model) { define_model_with_numbers }

      context "and attributes are seats \"12\" and email \"ann@example.com\"" do
        let(:attributes) { {"seats" => "12", "email" => "ann@example.com"} }

        # contract only
        it "answers an ActiveRecordModelRecord whose record is an unsaved record of the model" do
          expect(model_record).to be_a(Pipeforge::ActiveRecordModelRecord)
          expect(model_record.record).to be_a(model)
          expect(model_record.record).to be_new_record
        end

        # contract only
        it "gives the record the cast values" do
          expect(model_record.record).to have_attributes(seats: 12, email: "ann@example.com")
        end

        # contract only
        it "sends no statement other than a schema read to the database" do
          target

          expect(statement_names { model_record }.uniq - ["SCHEMA"]).to be_empty
        end
      end
    end

    context "when model is ModelWithBoolean, whose active column has the default true" do
      let(:model) { define_model_with_boolean }

      context "and attributes are active nil" do
        let(:attributes) { {"active" => nil} }

        it "gives the record nil for active, not the default" do
          expect(model_record.record.active).to be_nil
        end
      end
    end

    context "when model is ModelWithEnum" do
      let(:model) { define_model_with_enum }

      context "and attributes are tier \"pro\"" do
        let(:attributes) { {"tier" => "pro"} }

        it "gives the record the tier \"pro\"" do
          expect(model_record.record.tier).to eq("pro")
        end
      end

      context "and attributes are kind \"wholesale\", an enum stored as text" do
        let(:attributes) { {"kind" => "wholesale"} }

        # contract only
        it "gives the record the kind \"wholesale\"" do
          expect(model_record.record.kind).to eq("wholesale")
        end
      end

      context "and attributes are tier \"1\", the stored value written as text" do
        let(:attributes) { {"tier" => "1"} }

        it "gives the record the value_not_accepted_enum_label error for tier, with the value \"1\"" do
          expect(model_record.errors["tier"]).to eq(
            catalog_error(key: :value_not_accepted_enum_label, target_column_name: "tier", value: "1")
          )
        end
      end

      context "and attributes are tier 0, the stored value as a number" do
        let(:attributes) { {"tier" => 0} }

        it "leaves the tier of the record nil" do
          expect(model_record.record.tier).to be_nil
        end
      end

      context "and attributes are tier \"gold\", a label the model does not know, and note \"x\"" do
        let(:attributes) { {"tier" => "gold", "note" => "x"} }

        it "leaves the tier of the record nil" do
          expect(model_record.record.tier).to be_nil
        end

        # contract only
        it "gives the record the note \"x\"" do
          expect(model_record.record.note).to eq("x")
        end
      end
    end

    context "when model is ModelWithJson" do
      let(:model) { define_model_with_json }

      context "and attributes are settings of a JSON text" do
        let(:attributes) { {"settings" => '{"theme":"dark"}'} }

        it "gives the record the Hash for settings" do
          expect(model_record.record.settings).to eq("theme" => "dark")
        end
      end

      context "and attributes are settings \"null\"" do
        let(:attributes) { {"settings" => "null"} }

        # contract only
        it "gives the record no error" do
          expect(model_record.errors).to be_empty
        end
      end

      context "and attributes are settings of a Hash" do
        let(:attributes) { {"settings" => {"theme" => "dark"}} }

        # contract only
        it "gives the record the Hash for settings" do
          expect(model_record.record.settings).to eq("theme" => "dark")
        end
      end

      context "and attributes are settings \"{oops\", a text that is not JSON" do
        let(:attributes) { {"settings" => "{oops"} }

        it "gives the record the value_not_accepted_not_castable error for settings, with the value as it was given" do
          expect(model_record.errors["settings"]).to eq(
            catalog_error(key: :value_not_accepted_not_castable, target_column_name: "settings", value: "{oops")
          )
        end
      end
    end

    context "when model is ModelWithDates" do
      let(:model) { define_model_with_dates }

      context "and attributes are starts_on \"2024-02-30\", a day that is not in the calendar" do
        let(:attributes) { {"starts_on" => "2024-02-30"} }

        it "gives the record the value_not_accepted_not_castable error for starts_on, with the value \"2024-02-30\"" do
          expect(model_record.errors["starts_on"]).to eq(
            catalog_error(key: :value_not_accepted_not_castable, target_column_name: "starts_on", value: "2024-02-30")
          )
        end
      end
    end

    context "when model is ModelWithPolymorphicParent" do
      let(:model) { define_model_with_polymorphic_parent }

      context "and commentable_type names a model" do
        let(:attributes) { {"commentable_id" => 1, "commentable_type" => "AdapterSpecModels::Company"} }

        # contract only
        it "gives the record the commentable_id and the commentable_type" do
          expect(model_record.record).to have_attributes(commentable_id: 1, commentable_type: "AdapterSpecModels::Company")
        end
      end

      context "and commentable_type is \"Post\", which names no model" do
        let(:attributes) { {"commentable_id" => 1, "commentable_type" => "Post"} }

        it "leaves the commentable_type of the record nil" do
          expect(model_record.record.commentable_type).to be_nil
        end

        it "gives the record the value_not_accepted_polymorphic_type error for commentable_type, with the value \"Post\"" do
          expect(model_record.errors["commentable_type"]).to eq(
            catalog_error(key: :value_not_accepted_polymorphic_type, target_column_name: "commentable_type", value: "Post")
          )
        end
      end

      context "and commentable_type is \"String\", a class that is not a model" do
        let(:attributes) { {"commentable_id" => 1, "commentable_type" => "String"} }

        it "leaves the commentable_type of the record nil" do
          expect(model_record.record.commentable_type).to be_nil
        end
      end

      context "and commentable_type is \"AdapterSpecModels::AbstractRecord\", an abstract class" do
        let(:attributes) { {"commentable_id" => 1, "commentable_type" => "AdapterSpecModels::AbstractRecord"} }

        it "leaves the commentable_type of the record nil" do
          expect(model_record.record.commentable_type).to be_nil
        end
      end

      context "and commentable_type is nil" do
        let(:attributes) { {"commentable_id" => 1, "commentable_type" => nil} }

        # contract only
        it "gives the record no error" do
          expect(model_record.errors).to be_empty
        end
      end
    end

    context "when model is ModelWithEnumAndDate" do
      let(:model) { define_model_with_enum_and_date }

      context "and attributes are tier \"gold\" and starts_on \"2024-02-30\", two rejected values" do
        let(:attributes) { {"tier" => "gold", "starts_on" => "2024-02-30"} }

        it "gives the record one error for tier and one for starts_on" do
          expect(model_record.errors.keys).to contain_exactly("tier", "starts_on")
        end
      end
    end
  end

  describe "#cast_value" do
    subject(:cast_result) { target.cast_value(column_name: column_name, value: value) }

    context "when model is ModelWithNumbers" do
      let(:model) { define_model_with_numbers }

      context "and column_name is seats" do
        let(:column_name) { "seats" }

        context "and value is \"12\"" do
          let(:value) { "12" }

          # contract only
          it "answers castable, with the cast_value 12 and the json_value 12" do
            expect(cast_result).to eq(Pipeforge::CastResult.new(castable: true, cast_value: 12, json_value: 12))
          end
        end

        context "and value is \"abc\"" do
          let(:value) { "abc" }

          # The cast is lenient: ActiveRecord reads "abc" in an integer column as 0.
          # contract only
          it "answers castable, with the cast_value 0" do
            expect(cast_result).to eq(Pipeforge::CastResult.new(castable: true, cast_value: 0, json_value: 0))
          end
        end

        context "and value is 12, as a value mapping gives it" do
          let(:value) { 12 }

          # contract only
          it "answers castable, with the cast_value 12" do
            expect(cast_result).to eq(Pipeforge::CastResult.new(castable: true, cast_value: 12, json_value: 12))
          end
        end

        context "and value is nil" do
          let(:value) { nil }

          it "answers CastResult::NOT_CASTABLE" do
            expect(cast_result).to eq(Pipeforge::CastResult::NOT_CASTABLE)
          end
        end

        context "and value is \"99999\", outside the range of the column" do
          let(:value) { "99999" }

          # The range is checked elsewhere.
          # contract only
          it "answers castable, with the cast_value 99_999" do
            expect(cast_result).to eq(Pipeforge::CastResult.new(castable: true, cast_value: 99_999, json_value: 99_999))
          end
        end
      end

      context "and column_name is fee, a decimal with scale 2" do
        let(:column_name) { "fee" }

        context "and value is \"12.345\"" do
          let(:value) { "12.345" }

          it "answers the cast_value rounded to the scale and the json_value \"12.35\"" do
            expect(cast_result).to eq(Pipeforge::CastResult.new(castable: true, cast_value: BigDecimal("12.35"), json_value: "12.35"))
          end
        end
      end

      context "and column_name is email, a string" do
        let(:column_name) { "email" }

        context "and value is a text" do
          let(:value) { "ann@example.com" }

          # contract only
          it "answers the text as it is" do
            expect(cast_result).to eq(
              Pipeforge::CastResult.new(castable: true, cast_value: "ann@example.com", json_value: "ann@example.com")
            )
          end
        end
      end

      context "and column_name is not a column of the table" do
        let(:column_name) { "nope" }

        context "and value is a text" do
          let(:value) { "x" }

          # contract only
          it "answers castable, with the text as it is" do
            expect(cast_result).to eq(Pipeforge::CastResult.new(castable: true, cast_value: "x", json_value: "x"))
          end
        end
      end

      context "and column_name is seats and value is \"12\"" do
        let(:column_name) { "seats" }
        let(:value) { "12" }

        # contract only
        it "sends no statement other than a schema read to the database" do
          target

          expect(statement_names { cast_result }.uniq - ["SCHEMA"]).to be_empty
        end
      end
    end

    context "when model is ModelWithBoolean" do
      let(:model) { define_model_with_boolean }
      let(:column_name) { "active" }

      context "and value is \"yes\"" do
        let(:value) { "yes" }

        # contract only
        it "answers castable, with the cast_value true and the json_value true" do
          expect(cast_result).to eq(Pipeforge::CastResult.new(castable: true, cast_value: true, json_value: true))
        end
      end

      context "and value is false" do
        let(:value) { false }

        # contract only
        it "answers castable, with the cast_value false" do
          expect(cast_result).to eq(Pipeforge::CastResult.new(castable: true, cast_value: false, json_value: false))
        end
      end
    end

    context "when model is ModelWithDates" do
      let(:model) { define_model_with_dates }

      context "and column_name is starts_on" do
        let(:column_name) { "starts_on" }

        context "and value is \"2024-2-3\"" do
          let(:value) { "2024-2-3" }

          it "answers the cast_value Date.new(2024, 2, 3) and the json_value \"2024-02-03\"" do
            expect(cast_result).to eq(
              Pipeforge::CastResult.new(castable: true, cast_value: Date.new(2024, 2, 3), json_value: "2024-02-03")
            )
          end
        end

        context "and value is \"garbage\"" do
          let(:value) { "garbage" }

          it "answers CastResult::NOT_CASTABLE" do
            expect(cast_result).to eq(Pipeforge::CastResult::NOT_CASTABLE)
          end
        end
      end

      context "and column_name is starts_at" do
        let(:column_name) { "starts_at" }

        context "and value is \"2024-02-03 10:00:00 +0530\"" do
          let(:value) { "2024-02-03 10:00:00 +0530" }

          # contract only
          it "answers a Time as the cast_value and the json_value \"2024-02-03T10:00:00.000+05:30\"" do
            expect(cast_result.cast_value).to be_a(Time)
            expect(cast_result.json_value).to eq("2024-02-03T10:00:00.000+05:30")
          end
        end
      end
    end

    context "when model is ModelWithJson" do
      let(:model) { define_model_with_json }

      context "and column_name is settings" do
        let(:column_name) { "settings" }

        context "and value is the text of an object" do
          let(:value) { '{"theme":"dark","size":3}' }

          it "answers the Hash it describes as the cast_value and as the json_value" do
            expect(cast_result).to eq(
              Pipeforge::CastResult.new(
                castable: true, cast_value: {"theme" => "dark", "size" => 3}, json_value: {"theme" => "dark", "size" => 3}
              )
            )
          end
        end

        context "and value is \"[1,2]\"" do
          let(:value) { "[1,2]" }

          # contract only
          it "answers the Array [1, 2]" do
            expect(cast_result.cast_value).to eq([1, 2])
          end
        end

        context "and value is '\"hello\"', a JSON string with its quotes" do
          let(:value) { '"hello"' }

          # contract only
          it "answers the String \"hello\"" do
            expect(cast_result.cast_value).to eq("hello")
          end
        end

        context "and value is \"{oops\"" do
          let(:value) { "{oops" }

          it "answers CastResult::NOT_CASTABLE" do
            expect(cast_result).to eq(Pipeforge::CastResult::NOT_CASTABLE)
          end
        end

        context "and value is \"null\"" do
          let(:value) { "null" }

          # contract only
          it "answers castable, with nil as the cast_value and as the json_value" do
            expect(cast_result).to eq(Pipeforge::CastResult.new(castable: true, cast_value: nil, json_value: nil))
          end
        end

        context "and value is a Hash, as a value mapping gives it" do
          let(:value) { {"theme" => "dark"} }

          it "answers the Hash as it is" do
            expect(cast_result).to eq(
              Pipeforge::CastResult.new(castable: true, cast_value: {"theme" => "dark"}, json_value: {"theme" => "dark"})
            )
          end
        end

        context "and value is an Array" do
          let(:value) { [1, 2] }

          # contract only
          it "answers the Array as it is" do
            expect(cast_result.cast_value).to eq([1, 2])
          end
        end
      end

      context "and column_name is extras, a jsonb column" do
        let(:column_name) { "extras" }

        context "and value is the text of an object" do
          let(:value) { '{"beta":true}' }

          it "answers the Hash it describes" do
            expect(cast_result.cast_value).to eq("beta" => true)
          end
        end
      end
    end

    context "when model is ModelWithEnum" do
      let(:model) { define_model_with_enum }

      context "and column_name is tier" do
        let(:column_name) { "tier" }

        context "and value is the label \"pro\"" do
          let(:value) { "pro" }

          # contract only
          it "answers \"pro\" as it is" do
            expect(cast_result).to eq(Pipeforge::CastResult.new(castable: true, cast_value: "pro", json_value: "pro"))
          end
        end

        context "and value is \"1\", the stored value written as text" do
          let(:value) { "1" }

          # contract only
          it "answers \"1\" as it is" do
            expect(cast_result).to eq(Pipeforge::CastResult.new(castable: true, cast_value: "1", json_value: "1"))
          end
        end

        context "and value is 1, the stored value as a number" do
          let(:value) { 1 }

          # The number is not turned into the label.
          it "answers 1 as it is" do
            expect(cast_result).to eq(Pipeforge::CastResult.new(castable: true, cast_value: 1, json_value: 1))
          end
        end

        context "and value is \"nope\", a label the model does not know" do
          let(:value) { "nope" }

          # contract only
          it "answers castable, with \"nope\"" do
            expect(cast_result).to eq(Pipeforge::CastResult.new(castable: true, cast_value: "nope", json_value: "nope"))
          end
        end
      end
    end
  end

  describe "#transaction" do
    subject(:block_result) { target.transaction(rollback_at_end: rollback_at_end) { work.call } }

    let(:model) { define_model_with_email }
    let(:work) { -> { model.create!(email: "ann@example.com") } }

    context "when rollback_at_end is false" do
      let(:rollback_at_end) { false }

      context "and the block saves an email" do
        it "keeps the row" do
          block_result

          expect(model.pluck(:email)).to eq(["ann@example.com"])
        end
      end

      context "and the block answers :done" do
        let(:work) { -> { :done } }

        # contract only
        it "answers the result of the block" do
          expect(block_result).to eq(:done)
        end
      end

      context "and the block saves a row and raises" do
        let(:work) do
          lambda do
            model.create!(email: "ann@example.com")
            raise "stop"
          end
        end

        # contract only
        it "raises the error" do
          expect { block_result }.to raise_error(RuntimeError, "stop")
        end
      end
    end

    context "when rollback_at_end is true" do
      let(:rollback_at_end) { true }

      context "and the block answers :done" do
        let(:work) { -> { :done } }

        # The transaction is undone, and a rolled-back transaction returns nil.
        it "answers the result of the block" do
          expect(block_result).to eq(:done)
        end
      end

      context "and the block saves two rows, the second after reading the table" do
        subject(:emails_seen_by_second_row) do
          emails = nil
          target.transaction(rollback_at_end: rollback_at_end) do
            model.create!(email: "first@example.com")
            emails = model.pluck(:email)
            model.create!(email: "second@example.com")
          end
          emails
        end

        # contract only
        it "lets the second row see the first row" do
          expect(emails_seen_by_second_row).to eq(["first@example.com"])
        end
      end

      context "and a transaction of the consumer is already open, with a row they wrote before" do
        subject(:emails_kept) do
          emails = nil
          model.transaction do
            model.create!(email: "before@example.com")
            target.transaction(rollback_at_end: rollback_at_end) { model.create!(email: "dry@example.com") }
            emails = model.pluck(:email)
          end
          emails
        end

        it "undoes the row of the block and keeps the earlier row of the consumer" do
          expect(emails_kept).to eq(["before@example.com"])
        end
      end
    end

    context "when model is Reading, a model of another database, and rollback_at_end is true" do
      subject(:block_result) do
        target.transaction(rollback_at_end: true) { AdapterSpecModels::Reading.create!(label: "first") }
      end

      let(:model) { AdapterSpecModels::Reading }

      after { AdapterSpecModels::Reading.delete_all }

      it "does not keep the row, as the transaction is on the connection of the model" do
        block_result

        expect(AdapterSpecModels::Reading.count).to eq(0)
      end
    end
  end

  describe "#preload_parents" do
    subject(:preloaded_queries) do
      # The records, and the parents they point to, are made before the statements are counted.
      model_records
      queries_on(parent_table) { target.preload_parents(records: model_records) }
    end

    let(:parent_table) { "companies" }
    let(:acme) { AdapterSpecModels::Company.create!(name: "Acme") }
    let(:other_company) { AdapterSpecModels::Company.create!(name: "Other") }

    context "when model is ModelWithParent" do
      let(:model) { define_model_with_parent }

      context "and the records point to three companies, one of them missing" do
        let(:model_records) do
          [acme.id, other_company.id, acme.id, 999_999].map do |company_id|
            target.build_record(attributes: {"company_id" => company_id})
          end
        end

        it "loads the parents with one query on companies" do
          expect(preloaded_queries.size).to eq(1)
        end

        it "makes the validation of the records send no query to companies" do
          target.preload_parents(records: model_records)

          expect(queries_on("companies") { model_records.each(&:valid?) }).to be_empty
        end
      end

      context "and there are no records" do
        let(:model_records) { [] }

        # contract only
        it "sends no query" do
          expect(preloaded_queries).to be_empty
        end
      end
    end

    context "when model is ModelWithPolymorphicParent" do
      let(:model) { define_model_with_polymorphic_parent }

      context "and the records have two parents of one class" do
        let(:model_records) do
          [acme.id, other_company.id].map do |commentable_id|
            target.build_record(attributes: {"commentable_id" => commentable_id, "commentable_type" => "AdapterSpecModels::Company"})
          end
        end

        it "loads the parents with one query on companies" do
          expect(preloaded_queries.size).to eq(1)
        end

        it "makes commentable of each record available with no further query" do
          target.preload_parents(records: model_records)

          expect(queries_on("companies") { model_records.map { |model_record| model_record.record.commentable } }).to be_empty
        end
      end

      context "and one record has a commentable_type that was rejected, beside a record with a valid one" do
        let(:model_records) do
          [
            target.build_record(attributes: {"commentable_id" => acme.id, "commentable_type" => "AdapterSpecModels::Company"}),
            target.build_record(attributes: {"commentable_id" => 1, "commentable_type" => "Post"})
          ]
        end

        it "raises no error" do
          expect { preloaded_queries }.not_to raise_error
        end
      end
    end

    context "when model is ModelWithCompositeParent" do
      let(:model) { define_model_with_composite_parent }
      let(:parent_table) { "orders" }
      let(:model_records) do
        [2, 99].map { |order_number| target.build_record(attributes: {"shop_id" => 1, "order_number" => order_number}) }
      end

      before { AdapterSpecModels::Order.create!(shop_id: 1, number: 2) }

      after { AdapterSpecModels::Order.delete_all }

      context "and the records point to two orders" do
        it "loads the parents with one query on orders" do
          expect(preloaded_queries.size).to eq(1)
        end
      end
    end

    context "when model is ModelWithTwoParents" do
      let(:model) { define_model_with_two_parents }
      let(:model_records) do
        [acme.id, other_company.id].map do |company_id|
          target.build_record(attributes: {"from_company_id" => company_id, "to_company_id" => company_id})
        end
      end

      context "and there are two records" do
        it "sends one query for each of the two associations" do
          expect(preloaded_queries.size).to eq(2)
        end
      end
    end

    context "when model is ModelWithoutParent" do
      let(:model) { define_model_without_parent }
      let(:model_records) { [target.build_record(attributes: {"name" => "x"})] }

      context "and there is a record" do
        # contract only
        it "raises no error" do
          expect { preloaded_queries }.not_to raise_error
        end

        # contract only
        it "sends no query" do
          model_records

          expect(statement_names { target.preload_parents(records: model_records) }.uniq - ["SCHEMA"]).to be_empty
        end
      end
    end

    context "when model is ModelWithChildren, whose only association is a has_many" do
      let(:model) { define_model_with_children }
      let(:parent_table) { "model_with_parent_ids" }
      let(:model_records) { [target.build_record(attributes: {"id" => 1, "name" => "x"})] }

      it "sends no query" do
        expect(preloaded_queries).to be_empty
      end
    end
  end
end
