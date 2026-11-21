# frozen_string_literal: true

# The target works on a model, and ActiveRecord is a third-party gem, so every example uses a real model over a real
# table of the PostgreSQL test database, made by define_model in the example and dropped after it, and nothing of
# ActiveRecord is replaced by a double: a change in a new version of ActiveRecord shows here. The models are named for
# the fact they show. The only models taken from spec/support/active_record_helper.rb are the parents
# AdapterSpecModels::Company and AdapterSpecModels::Order, AdapterSpecModels::ModelInSecondaryDatabase and
# AdapterSpecModels::ModelWithTableOnlyInDefaultDatabase (another database) and AdapterSpecModels::AbstractModel.
# The only doubles are our own ActiveRecordSchemaReader (in the examples of #schema) and ActiveRecordModelRecord (in
# the examples of #build_record and #preload_parents).
# An example that no break fails alone is kept for what the rule accepts or reports (contract only).
RSpec.describe Pipeforge::ActiveRecordTarget do
  subject(:target) { described_class.new(target_model_name: model.name) }

  # The error of the ErrorCatalog for a value the record could not be given.
  def catalog_error(key:, target_column_name:, value:)
    Pipeforge::ErrorCatalog::ERRORS.fetch(key).call(origin: :model, target_column_name: target_column_name, value: value)
  end

  describe ".new" do
    subject(:target) { described_class.new(target_model_name: target_model_name) }

    context "when target_model_name is the name of a loaded model with a table" do
      let(:target_model_name) { define_model(name: "ModelWithNumbers").name }

      # contract only
      it "answers an ActiveRecordTarget" do
        expect(target).to be_an_instance_of(described_class)
      end
    end

    context "when target_model_name is the name of no loaded model" do
      let(:target_model_name) { "AdapterSpecModels::ModelNobodyLoaded" }

      it "raises TargetSchemaError with active_record_model_not_found, naming model_name" do
        expect { target }.to raise_error(Pipeforge::TargetSchemaError) do |error|
          expect(error.errors.first).to include(code: :active_record_model_not_found, model_name: "AdapterSpecModels::ModelNobodyLoaded")
        end
      end
    end

    context "when target_model_name is only the beginning of the name of a loaded model" do
      let(:target_model_name) { define_model(name: "ModelWithLongerName").name.delete_suffix("Name") }

      it "raises TargetSchemaError with active_record_model_not_found, naming model_name" do
        expect { target }.to raise_error(Pipeforge::TargetSchemaError) do |error|
          expect(error.errors.first).to include(code: :active_record_model_not_found, model_name: "AdapterSpecModels::ModelWithLonger")
        end
      end
    end

    context "when target_model_name is the name of an abstract class" do
      let(:target_model_name) { "AdapterSpecModels::AbstractModel" }

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

    context "when target_model_name is ModelInSecondaryDatabase, a model of another database whose table is there" do
      let(:target_model_name) { "AdapterSpecModels::ModelInSecondaryDatabase" }

      it "answers an ActiveRecordTarget" do
        expect(target).to be_an_instance_of(described_class)
      end
    end

    context "when target_model_name is ModelWithTableOnlyInDefaultDatabase, whose table is only in the default database" do
      let(:target_model_name) { "AdapterSpecModels::ModelWithTableOnlyInDefaultDatabase" }

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
      let(:model) do
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

      context "and column_name is tier, an enum stored as a number" do
        let(:column_name) { "tier" }

        it "answers the labels, not the stored numbers" do
          expect(enum_labels).to eq(%w[basic pro])
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

    context "when model is ModelWithoutParent, with no enum and no association" do
      let(:model) { define_model(name: "ModelWithoutParent", columns: ->(table) { table.string :name }) }

      # contract only
      it "answers what the schema reader answers" do
        expect(schema).to be(schema_from_reader)
      end
    end

    context "when model is ModelWithEnum" do
      let(:model) do
        define_model(
          name: "ModelWithEnum",
          columns: lambda do |table|
            table.integer :tier
            table.string :kind
          end
        ) do
          enum :tier, {basic: 0, pro: 1}
          enum :kind, {retail: "retail", wholesale: "wholesale"}
        end
      end

      it "builds the schema reader with the model, its enum_labels and no polymorphic_columns" do
        schema

        expect(Pipeforge::ActiveRecordSchemaReader).to have_received(:new).with(
          model: model,
          enum_labels_by_column_name: {"tier" => %w[basic pro], "kind" => %w[retail wholesale]},
          polymorphic_columns_by_column_name: {}
        )
      end
    end

    context "when model is ModelWithPolymorphicParent" do
      let(:model) do
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

      it "builds the schema reader with the id column and the type column of the association as polymorphic_columns" do
        schema

        expect(Pipeforge::ActiveRecordSchemaReader).to have_received(:new).with(
          model: model,
          enum_labels_by_column_name: {},
          polymorphic_columns_by_column_name: {
            "commentable_id" => Pipeforge::PolymorphicColumn.new(association_name: "commentable", role: "id"),
            "commentable_type" => Pipeforge::PolymorphicColumn.new(association_name: "commentable", role: "type")
          }
        )
      end
    end

    context "when model is ModelWithTwoPolymorphicParents" do
      let(:model) do
        define_model(
          name: "ModelWithTwoPolymorphicParents",
          columns: lambda do |table|
            table.integer :owner_id
            table.string :owner_type
            table.integer :target_id
            table.string :target_type
          end
        ) do
          belongs_to :owner, polymorphic: true
          belongs_to :target, polymorphic: true
        end
      end

      it "builds the schema reader with the id column and the type column of each association, each with its own association_name" do
        schema

        expect(Pipeforge::ActiveRecordSchemaReader).to have_received(:new).with(
          model: model,
          enum_labels_by_column_name: {},
          polymorphic_columns_by_column_name: {
            "owner_id" => Pipeforge::PolymorphicColumn.new(association_name: "owner", role: "id"),
            "owner_type" => Pipeforge::PolymorphicColumn.new(association_name: "owner", role: "type"),
            "target_id" => Pipeforge::PolymorphicColumn.new(association_name: "target", role: "id"),
            "target_type" => Pipeforge::PolymorphicColumn.new(association_name: "target", role: "type")
          }
        )
      end
    end

    context "when model is ModelWithParent, whose belongs_to is not polymorphic" do
      let(:model) do
        define_model(name: "ModelWithParent", columns: ->(table) { table.bigint :company_id }) do
          belongs_to :company, class_name: "AdapterSpecModels::Company", optional: false
        end
      end

      it "builds the schema reader with no polymorphic_columns" do
        schema

        expect(Pipeforge::ActiveRecordSchemaReader).to have_received(:new).with(
          model: model, enum_labels_by_column_name: {}, polymorphic_columns_by_column_name: {}
        )
      end
    end
  end

  describe "#cast_value" do
    subject(:cast_result) { target.cast_value(column_name: column_name, value: value) }

    context "when model is ModelWithNumbers" do
      let(:model) do
        define_model(
          name: "ModelWithNumbers",
          columns: lambda do |table|
            table.integer :seats, limit: 2
            table.decimal :fee, precision: 5, scale: 2
            table.string :email
          end
        )
      end

      context "and column_name is seats" do
        let(:column_name) { "seats" }

        context "and value is \"12\"" do
          let(:value) { "12" }

          # contract only
          it "answers a CastResult" do
            expect(cast_result).to be_an_instance_of(Pipeforge::CastResult)
          end

          it "answers castable, with the cast_value 12 and the json_value 12" do
            expect(cast_result).to eq(Pipeforge::CastResult.new(castable: true, cast_value: 12, json_value: 12))
          end

          # contract only
          it "sends no statement other than a schema read to the database" do
            target

            expect(statement_names { cast_result }.uniq - ["SCHEMA"]).to be_empty
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
    end

    context "when model is ModelWithBoolean" do
      let(:model) { define_model(name: "ModelWithBoolean", columns: ->(table) { table.boolean :active, default: true }) }
      let(:column_name) { "active" }

      context "and value is false" do
        let(:value) { false }

        # contract only
        it "answers castable, with the cast_value false" do
          expect(cast_result).to eq(Pipeforge::CastResult.new(castable: true, cast_value: false, json_value: false))
        end
      end
    end

    context "when model is ModelWithDates" do
      let(:model) do
        define_model(
          name: "ModelWithDates",
          columns: lambda do |table|
            table.date :starts_on
            table.datetime :starts_at
          end
        )
      end

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

        context "and value is \"2024-02-30\", a day that is not in the calendar" do
          let(:value) { "2024-02-30" }

          it "answers CastResult::NOT_CASTABLE" do
            expect(cast_result).to eq(Pipeforge::CastResult::NOT_CASTABLE)
          end
        end
      end

      context "and column_name is starts_at" do
        let(:column_name) { "starts_at" }

        context "and value is \"2024-02-03 10:00:00 +0530\"" do
          let(:value) { "2024-02-03 10:00:00 +0530" }

          it "answers a Time as the cast_value and the json_value \"2024-02-03T10:00:00.000+05:30\"" do
            expect(cast_result.cast_value).to be_a(Time)
            expect(cast_result.json_value).to eq("2024-02-03T10:00:00.000+05:30")
          end
        end
      end
    end

    context "when model is ModelWithJson" do
      let(:model) do
        define_model(
          name: "ModelWithJson",
          columns: lambda do |table|
            table.string :name
            table.json :settings
            table.jsonb :extras
          end
        )
      end

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

        context "and value is \"{oops\"" do
          let(:value) { "{oops" }

          it "answers CastResult::NOT_CASTABLE" do
            expect(cast_result).to eq(Pipeforge::CastResult::NOT_CASTABLE)
          end
        end

        context "and value is \"null\"" do
          let(:value) { "null" }

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
      let(:model) do
        define_model(name: "ModelWithEnum", columns: ->(table) { table.integer :tier }) do
          enum :tier, {basic: 0, pro: 1}
        end
      end

      context "and column_name is tier" do
        let(:column_name) { "tier" }

        context "and value is 1, the stored value as a number" do
          let(:value) { 1 }

          # The number is not turned into the label.
          it "answers 1 as it is" do
            expect(cast_result).to eq(Pipeforge::CastResult.new(castable: true, cast_value: 1, json_value: 1))
          end
        end
      end
    end
  end

  describe "#build_record" do
    subject(:built_record) { target.build_record(attributes: attributes) }

    let(:model_record) { instance_double(Pipeforge::ActiveRecordModelRecord, add_error: nil) }
    let(:handed_records) { [] }
    let(:handed_record) { handed_records.last }

    before do
      allow(Pipeforge::ActiveRecordModelRecord).to receive(:new) do |record:|
        handed_records << record
        model_record
      end
    end

    context "when model is ModelWithNumbers" do
      let(:model) do
        define_model(
          name: "ModelWithNumbers",
          columns: lambda do |table|
            table.integer :seats, limit: 2
            table.string :email
          end
        )
      end

      context "and attributes are email \"ann@example.com\", a value the record can hold" do
        let(:attributes) { {"email" => "ann@example.com"} }

        # contract only
        it "answers the model record that ActiveRecordModelRecord.new answered" do
          expect(built_record).to be(model_record)
        end

        it "builds the model record with an unsaved record of the model" do
          built_record

          expect(Pipeforge::ActiveRecordModelRecord).to have_received(:new).with(record: an_instance_of(model))
          expect(handed_record).to be_new_record
        end

        it "gives the model record a record that holds the email" do
          built_record

          expect(handed_record.email).to eq("ann@example.com")
        end

        # contract only
        it "adds no error" do
          built_record

          expect(model_record).not_to have_received(:add_error)
        end

        # contract only
        it "sends no statement other than a schema read to the database" do
          target

          expect(statement_names { built_record }.uniq - ["SCHEMA"]).to be_empty
        end
      end
    end

    context "when model is ModelWithEnum" do
      let(:model) do
        define_model(name: "ModelWithEnum", columns: ->(table) { table.integer :tier }) do
          enum :tier, {basic: 0, pro: 1}
        end
      end

      context "and attributes are tier \"pro\", a label of the enum" do
        let(:attributes) { {"tier" => "pro"} }

        it "adds no error" do
          built_record

          expect(model_record).not_to have_received(:add_error)
        end
      end

      context "and attributes are tier nil" do
        let(:attributes) { {"tier" => nil} }

        it "adds no error" do
          built_record

          expect(model_record).not_to have_received(:add_error)
        end
      end

      context "and attributes are tier \"1\", the stored value written as text" do
        let(:attributes) { {"tier" => "1"} }

        it "adds the value_not_accepted_enum_label error for tier, with the value \"1\"" do
          built_record

          expect(model_record).to have_received(:add_error).with(
            error: catalog_error(key: :value_not_accepted_enum_label, target_column_name: "tier", value: "1")
          )
        end

        it "gives the model record a record that holds nil for tier" do
          built_record

          expect(handed_record.tier).to be_nil
        end
      end

      context "and attributes are tier 0, the stored value as a number" do
        let(:attributes) { {"tier" => 0} }

        it "adds the value_not_accepted_enum_label error for tier, with the value 0" do
          built_record

          expect(model_record).to have_received(:add_error).with(
            error: catalog_error(key: :value_not_accepted_enum_label, target_column_name: "tier", value: 0)
          )
        end
      end

      context "and attributes are tier \"gold\", a label the model does not know" do
        let(:attributes) { {"tier" => "gold"} }

        it "adds the value_not_accepted_enum_label error for tier, with the value \"gold\"" do
          built_record

          expect(model_record).to have_received(:add_error).with(
            error: catalog_error(key: :value_not_accepted_enum_label, target_column_name: "tier", value: "gold")
          )
        end

        it "does not raise" do
          expect { built_record }.not_to raise_error
        end
      end
    end

    context "when model is ModelWithJson" do
      let(:model) { define_model(name: "ModelWithJson", columns: ->(table) { table.json :settings }) }

      context "and attributes are settings of a JSON text" do
        let(:attributes) { {"settings" => '{"theme":"dark"}'} }

        # contract only
        it "adds no error" do
          built_record

          expect(model_record).not_to have_received(:add_error)
        end
      end

      context "and attributes are settings nil" do
        let(:attributes) { {"settings" => nil} }

        it "adds no error" do
          built_record

          expect(model_record).not_to have_received(:add_error)
        end
      end

      context "and attributes are settings \"{oops\", a text that is not JSON" do
        let(:attributes) { {"settings" => "{oops"} }

        it "adds the value_not_accepted_not_castable error for settings, with the value as it was given" do
          built_record

          expect(model_record).to have_received(:add_error).with(
            error: catalog_error(key: :value_not_accepted_not_castable, target_column_name: "settings", value: "{oops")
          )
        end

        it "gives the model record a record that holds nil for settings" do
          built_record

          expect(handed_record.settings).to be_nil
        end
      end
    end

    context "when model is ModelWithDates" do
      let(:model) { define_model(name: "ModelWithDates", columns: ->(table) { table.date :starts_on }) }

      context "and attributes are starts_on \"2024-02-30\", a day that is not in the calendar" do
        let(:attributes) { {"starts_on" => "2024-02-30"} }

        it "adds the value_not_accepted_not_castable error for starts_on, with the value as it was given" do
          built_record

          expect(model_record).to have_received(:add_error).with(
            error: catalog_error(key: :value_not_accepted_not_castable, target_column_name: "starts_on", value: "2024-02-30")
          )
        end
      end
    end

    context "when model is ModelWithPolymorphicParent" do
      let(:model) do
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

      context "and attributes are commentable_type \"AdapterSpecModels::Company\", a type that names a model" do
        let(:attributes) { {"commentable_type" => "AdapterSpecModels::Company"} }

        # contract only
        it "adds no error" do
          built_record

          expect(model_record).not_to have_received(:add_error)
        end
      end

      context "and attributes are commentable_type nil" do
        let(:attributes) { {"commentable_type" => nil} }

        it "adds no error" do
          built_record

          expect(model_record).not_to have_received(:add_error)
        end
      end

      context "and attributes are commentable_type \"Post\", a type that names no model" do
        let(:attributes) { {"commentable_type" => "Post"} }

        it "adds the value_not_accepted_polymorphic_type error for commentable_type, with the value \"Post\"" do
          built_record

          expect(model_record).to have_received(:add_error).with(
            error: catalog_error(key: :value_not_accepted_polymorphic_type, target_column_name: "commentable_type", value: "Post")
          )
        end

        it "gives the model record a record that holds nil for commentable_type" do
          built_record

          expect(handed_record.commentable_type).to be_nil
        end
      end

      context "and attributes are commentable_type \"String\", a class that is not a model" do
        let(:attributes) { {"commentable_type" => "String"} }

        it "adds the value_not_accepted_polymorphic_type error for commentable_type, with the value \"String\"" do
          built_record

          expect(model_record).to have_received(:add_error).with(
            error: catalog_error(key: :value_not_accepted_polymorphic_type, target_column_name: "commentable_type", value: "String")
          )
        end
      end

      context "and attributes are commentable_type \"AdapterSpecModels::AbstractModel\", an abstract class" do
        let(:attributes) { {"commentable_type" => "AdapterSpecModels::AbstractModel"} }

        it "adds the value_not_accepted_polymorphic_type error for commentable_type, with that value" do
          built_record

          expect(model_record).to have_received(:add_error).with(
            error: catalog_error(
              key: :value_not_accepted_polymorphic_type,
              target_column_name: "commentable_type",
              value: "AdapterSpecModels::AbstractModel"
            )
          )
        end
      end
    end

    context "when model is ModelWithEnumAndDate" do
      let(:model) do
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

      context "and attributes are tier \"gold\" and starts_on \"2024-02-30\", two rejected values on two columns" do
        let(:attributes) { {"tier" => "gold", "starts_on" => "2024-02-30"} }

        it "adds one error for tier and one for starts_on" do
          built_record

          expect(model_record).to have_received(:add_error).with(
            error: catalog_error(key: :value_not_accepted_enum_label, target_column_name: "tier", value: "gold")
          )
          expect(model_record).to have_received(:add_error).with(
            error: catalog_error(key: :value_not_accepted_not_castable, target_column_name: "starts_on", value: "2024-02-30")
          )
        end
      end
    end
  end

  describe "#preload_parents" do
    subject(:answer) { target.preload_parents(records: model_records) }

    let(:model_records) do
      unsaved_records.map { |unsaved_record| instance_double(Pipeforge::ActiveRecordModelRecord, record: unsaved_record) }
    end
    let(:acme) { AdapterSpecModels::Company.create!(name: "Acme") }
    let(:other_company) { AdapterSpecModels::Company.create!(name: "Other") }
    let(:third_company) { AdapterSpecModels::Company.create!(name: "Third") }

    # The statements that the call sends, with the target, the records and the parents they point to made before.
    def statements_sent_by_call
      target
      model_records
      statement_names { answer }.uniq - ["SCHEMA"]
    end

    context "when model is ModelWithParent" do
      let(:model) do
        define_model(name: "ModelWithParent", columns: ->(table) { table.bigint :company_id }) do
          belongs_to :company, class_name: "AdapterSpecModels::Company", optional: false
        end
      end

      context "and the records point to three companies" do
        let(:unsaved_records) do
          [acme, other_company, third_company, acme].map { |company| model.new(company_id: company.id) }
        end

        it "loads the parents with one query on companies" do
          target
          model_records

          expect(queries_on("companies") { answer }.size).to eq(1)
        end

        it "loads the parent of each record" do
          answer

          expect(unsaved_records.map { |unsaved_record| unsaved_record.association(:company).loaded? }).to all(be(true))
          expect(unsaved_records.map { |unsaved_record| unsaved_record.company.name }).to eq(%w[Acme Other Third Acme])
        end
      end

      context "and a record points to a company that does not exist" do
        let(:unsaved_records) { [model.new(company_id: 999_999)] }

        it "leaves the parent of the record nil" do
          answer

          expect(unsaved_records.first.company).to be_nil
        end
      end

      context "and there are no records" do
        let(:unsaved_records) { [] }

        # contract only
        it "sends no query" do
          expect(statements_sent_by_call).to be_empty
        end
      end
    end

    context "when model is ModelWithPolymorphicParent" do
      let(:model) do
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

      context "and the records have two parents of one class" do
        let(:unsaved_records) do
          [acme, other_company].map do |company|
            model.new(commentable_id: company.id, commentable_type: "AdapterSpecModels::Company")
          end
        end

        it "loads the parents with one query on companies" do
          target
          model_records

          expect(queries_on("companies") { answer }.size).to eq(1)
        end

        it "loads the parent of each record" do
          answer

          expect(unsaved_records.map { |unsaved_record| unsaved_record.commentable.name }).to eq(%w[Acme Other])
        end
      end

      context "and one record has commentable_type nil, beside a record with a valid one" do
        let(:unsaved_records) do
          [
            model.new(commentable_id: acme.id, commentable_type: "AdapterSpecModels::Company"),
            model.new(commentable_id: 1, commentable_type: nil)
          ]
        end

        it "raises no error" do
          expect { answer }.not_to raise_error
        end
      end
    end

    context "when model is ModelWithCompositeParent" do
      let(:model) do
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
      let(:unsaved_records) { [2, 99].map { |order_number| model.new(shop_id: 1, order_number: order_number) } }

      before { AdapterSpecModels::Order.create!(shop_id: 1, number: 2) }

      after { AdapterSpecModels::Order.delete_all }

      context "and the records point to two orders" do
        it "loads the parents with one query on orders" do
          target
          model_records

          expect(queries_on("orders") { answer }.size).to eq(1)
        end
      end
    end

    context "when model is ModelWithTwoParents" do
      let(:model) do
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
      let(:unsaved_records) do
        [acme, other_company].map { |company| model.new(from_company_id: company.id, to_company_id: company.id) }
      end

      context "and there are two records" do
        it "sends one query for each of the two associations" do
          target
          model_records

          expect(queries_on("companies") { answer }.size).to eq(2)
        end
      end
    end

    context "when model is ModelWithoutParent" do
      let(:model) { define_model(name: "ModelWithoutParent", columns: ->(table) { table.string :name }) }
      let(:unsaved_records) { [model.new(name: "x")] }

      context "and there is a record" do
        # contract only
        it "sends no query" do
          expect(statements_sent_by_call).to be_empty
        end
      end
    end

    context "when model is ModelWithChildren, whose only association is a has_many" do
      let(:model) do
        define_model(name: "ModelWithParentId", columns: ->(table) { table.integer :parent_id })
        define_model(name: "ModelWithChildren", columns: ->(table) { table.string :name }) do
          has_many :children, class_name: "AdapterSpecModels::ModelWithParentId", foreign_key: :parent_id
        end
      end
      let(:unsaved_records) { [model.new(id: 1, name: "x")] }

      it "sends no query" do
        expect(statements_sent_by_call).to be_empty
      end
    end
  end

  describe "#transaction" do
    subject(:block_result) { target.transaction(rollback_at_end: rollback_at_end) { work.call } }

    let(:model) { define_model(name: "ModelWithEmail", columns: ->(table) { table.string :email }) }
    let(:work) { -> { model.create!(email: "ann@example.com") } }

    context "when rollback_at_end is false" do
      let(:rollback_at_end) { false }

      context "and the block saves an email" do
        it "keeps the row" do
          block_result

          expect(model.pluck(:email)).to eq(["ann@example.com"])
        end
      end
    end

    context "when rollback_at_end is true" do
      let(:rollback_at_end) { true }

      context "and the block saves an email" do
        it "does not keep the row" do
          block_result

          expect(model.count).to eq(0)
        end
      end

      context "and the block answers :done" do
        let(:work) { -> { :done } }

        # The transaction is undone, and a rolled-back transaction returns nil.
        it "answers the result of the block" do
          expect(block_result).to eq(:done)
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

    context "when model is ModelInSecondaryDatabase, a model of another database, and rollback_at_end is true" do
      subject(:block_result) do
        target.transaction(rollback_at_end: true) { AdapterSpecModels::ModelInSecondaryDatabase.create!(label: "first") }
      end

      let(:model) { AdapterSpecModels::ModelInSecondaryDatabase }

      after { AdapterSpecModels::ModelInSecondaryDatabase.delete_all }

      it "does not keep the row, as the transaction is on the connection of the model" do
        block_result

        expect(AdapterSpecModels::ModelInSecondaryDatabase.count).to eq(0)
      end
    end
  end
end
