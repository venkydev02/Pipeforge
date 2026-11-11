# frozen_string_literal: true

RSpec.describe Pipeforge::ActiveRecordAdapter do
  subject(:adapter) { described_class.new }

  # The column of the schema with that name.
  def column_named(schema, name)
    schema.columns.find { |target_column| target_column.name == name }
  end

  describe "#schema" do
    subject(:schema) { adapter.schema(target_model: target_model) }

    let(:target_model) { "AdapterSpecModels::User" }

    it "names the table and the model" do
      expect(schema).to have_attributes(table_name: "users", model: "AdapterSpecModels::User")
    end

    it "lists the columns that can be given a source column, in table order" do
      expect(schema.columns.map(&:name)).to eq(
        %w[email age balance bio active company_id created_at updated_at]
      )
    end

    it "gives the character limit of a string column as max_length" do
      expect(column_named(schema, "email")).to have_attributes(
        type: "string", sql_type: "varchar(255)", max_length: 255, limit: nil
      )
    end

    it "gives the size in bytes of an integer column as limit" do
      expect(column_named(schema, "age")).to have_attributes(type: "integer", limit: 2, max_length: nil)
    end

    context "with a bigint column and an integer column declared with no size" do
      let(:target_model) { "AdapterSpecModels::Quantity" }

      it "gives 8 bytes as the limit of the bigint column" do
        expect(column_named(schema, "big_count")).to have_attributes(type: "integer", limit: 8)
      end

      context "and the database is SQLite" do
        it "gives 8 bytes as the limit of the integer column, the size SQLite holds", :sqlite_only do
          expect(column_named(schema, "plain_count")).to have_attributes(type: "integer", limit: 8)
        end
      end

      context "and the database is PostgreSQL" do
        it "gives 4 bytes as the limit of the integer column, the size of its integer type", :postgresql_only do
          expect(column_named(schema, "plain_count")).to have_attributes(type: "integer", limit: 4)
        end
      end
    end

    it "reports an integer column as signed" do
      expect(column_named(schema, "age")).to have_attributes(unsigned: false)
    end

    it "reports a column that is not an integer as not unsigned" do
      expect(column_named(schema, "email")).to have_attributes(unsigned: false)
    end

    context "with an attribute of ActiveRecord's unsigned integer type" do
      let(:target_model) { "AdapterSpecModels::Counter" }

      it "reports that column as unsigned, with its size" do
        expect(column_named(schema, "hits")).to have_attributes(type: "integer", limit: 2, unsigned: true)
      end

      it "reports the other integer column of the table as signed" do
        expect(column_named(schema, "misses")).to have_attributes(type: "integer", limit: 2, unsigned: false)
      end
    end

    context "with float columns" do
      let(:target_model) { "AdapterSpecModels::Measurement" }

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

    context "when the table has array columns", :postgresql_only do
      let(:target_model) { "AdapterSpecModels::Playlist" }

      it "lists only the column that is not an array" do
        expect(schema.columns.map(&:name)).to eq(%w[title])
      end
    end

    it "offers the timestamps for mapping" do
      expect(schema.columns.select { |target_column| target_column.name.end_with?("_at") }).to all(have_attributes(type: "datetime"))
    end

    it "describes a foreign key with its association and parent table" do
      expect(column_named(schema, "company_id").foreign_key).to eq(
        Pipeforge::ForeignKey.new(association: "company", parent_table: "companies")
      )
    end

    it "gives no foreign key for a column that is not one" do
      expect(column_named(schema, "email").foreign_key).to be_nil
    end

    context "with a column the model declares with another type than the table" do
      let(:target_model) { "AdapterSpecModels::Ticket" }

      it "gives the type the model declares" do
        expect(column_named(schema, "rank")).to have_attributes(type: "integer", sql_type: "varchar")
      end

      context "and the database is PostgreSQL" do
        it "gives no limit, because the model declares the integer with no size", :postgresql_only do
          expect(column_named(schema, "rank").limit).to be_nil
        end
      end
    end

    context "with enum columns and a default set only in the model" do
      let(:target_model) { "AdapterSpecModels::Shipment" }

      it "gives the labels and stored values of an enum stored as a number" do
        expect(column_named(schema, "status").enum_values).to eq("draft" => 0, "placed" => 1, "shipped" => 2)
      end

      it "gives the labels and stored values of an enum stored as text" do
        expect(column_named(schema, "kind").enum_values).to eq("retail" => "retail", "wholesale" => "wholesale")
      end

      it "gives no enum values for a column that is not an enum" do
        expect(column_named(schema, "note").enum_values).to be_nil
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
      let(:target_model) { "AdapterSpecModels::Receipt" }

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
        let(:target_model) { "AdapterSpecModels::Invoice" }

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
      let(:target_model) { "AdapterSpecModels::Comment" }

      it "does not describe its column as a foreign key" do
        expect(column_named(schema, "commentable_id").foreign_key).to be_nil
      end
    end

    context "with a composite foreign key" do
      let(:target_model) { "AdapterSpecModels::OrderLine" }

      it "does not describe its columns as foreign keys" do
        expect(schema.columns.map(&:foreign_key)).to all(be_nil)
      end
    end

    context "with a composite primary key" do
      let(:target_model) { "AdapterSpecModels::Order" }

      it "leaves out every column of the key" do
        expect(schema.columns).to be_empty
      end
    end

    context "when the model is a subclass under single table inheritance" do
      let(:target_model) { "AdapterSpecModels::Car" }

      it "reads the model named, with the table it shares with its base class" do
        expect(schema).to have_attributes(table_name: "vehicles", model: "AdapterSpecModels::Car")
      end
    end

    context "when two unrelated models share one table" do
      let(:target_model) { "AdapterSpecModels::Note" }

      it "reads the model named, and not the other one" do
        expect(schema).to have_attributes(table_name: "notes", model: "AdapterSpecModels::Note")
      end
    end

    context "when the table of the model does not exist" do
      let(:target_model) { "AdapterSpecModels::Ghost" }

      it "stops with target_table_not_found and the table of the model" do
        expect { schema }.to raise_error(Pipeforge::TargetSchemaError) do |error|
          expect(error.errors.first).to include(code: :target_table_not_found, table: "ghosts")
        end
      end
    end

    context "when the model uses another database and its table is there" do
      let(:target_model) { "AdapterSpecModels::Reading" }

      it "reads the table in the database of the model" do
        expect(schema).to have_attributes(table_name: "readings", model: "AdapterSpecModels::Reading")
        expect(schema.columns.map(&:name)).to eq(%w[label])
      end
    end

    context "when the model uses another database and its table is only in the default database" do
      let(:target_model) { "AdapterSpecModels::UserInOtherDatabase" }

      it "stops with target_table_not_found and the table of the model" do
        expect { schema }.to raise_error(Pipeforge::TargetSchemaError) do |error|
          expect(error.errors.first).to include(code: :target_table_not_found, table: "users")
        end
      end
    end

    context "when no loaded model has the name" do
      let(:target_model) { "AdapterSpecModels::Nowhere" }

      it "stops with active_record_model_not_found and the name" do
        expect { schema }.to raise_error(Pipeforge::TargetSchemaError) do |error|
          expect(error.errors.first).to include(code: :active_record_model_not_found, model: "AdapterSpecModels::Nowhere")
        end
      end
    end

    context "when the model named is an abstract class" do
      let(:target_model) { "AdapterSpecModels::AbstractRecord" }

      it "stops with active_record_model_not_found and the name" do
        expect { schema }.to raise_error(Pipeforge::TargetSchemaError) do |error|
          expect(error.errors.first).to include(code: :active_record_model_not_found, model: "AdapterSpecModels::AbstractRecord")
        end
      end
    end

    it "reads no row of the table, only its structure" do
      statement_names = []
      subscription = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        statement_names << payload[:name]
      end

      adapter.schema(target_model: "AdapterSpecModels::User")
      ActiveSupport::Notifications.unsubscribe(subscription)

      expect(statement_names.uniq).to eq(["SCHEMA"])
    end
  end

  describe "#model_adapter" do
    it "gives the model adapter of the model named" do
      expect(adapter.model_adapter(target_model: "AdapterSpecModels::Membership")).to be_a(Pipeforge::ActiveRecordModelAdapter)
    end

    it "builds the records of that model" do
      model_record = adapter.model_adapter(target_model: "AdapterSpecModels::Membership")
        .build_record(attributes: {"email" => "a@example.com"})

      expect(model_record.record).to be_a(AdapterSpecModels::Membership)
    end

    it "gives the model adapter of a model that uses another database" do
      expect(adapter.model_adapter(target_model: "AdapterSpecModels::Reading")).to be_a(Pipeforge::ActiveRecordModelAdapter)
    end

    it "stops with target_table_not_found when the table of the model does not exist" do
      expect { adapter.model_adapter(target_model: "AdapterSpecModels::Ghost") }.to raise_error(Pipeforge::TargetSchemaError) do |error|
        expect(error.codes).to eq([:target_table_not_found])
      end
    end

    it "stops with active_record_model_not_found when no loaded model has the name" do
      expect { adapter.model_adapter(target_model: "AdapterSpecModels::Nowhere") }.to raise_error(Pipeforge::TargetSchemaError) do |error|
        expect(error.codes).to eq([:active_record_model_not_found])
      end
    end
  end

  describe "the core's target adapter" do
    it "is this adapter, once the gem is loaded" do
      expect(Pipeforge::TargetAdapter.schema(target_model: "AdapterSpecModels::User").model).to eq("AdapterSpecModels::User")
    end

    it "gives the model adapter of this adapter" do
      expect(Pipeforge::TargetAdapter.model_adapter(target_model: "AdapterSpecModels::Membership")).to be_a(Pipeforge::ActiveRecordModelAdapter)
    end
  end
end
