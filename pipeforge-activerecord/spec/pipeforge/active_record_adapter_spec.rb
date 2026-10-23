# frozen_string_literal: true

RSpec.describe Pipeforge::ActiveRecordAdapter do
  subject(:adapter) { described_class.new }

  # The column of the schema with that name.
  def column_named(schema, name)
    schema.columns.find { |target_column| target_column.name == name }
  end

  describe "#schema" do
    subject(:schema) { adapter.schema(target_table: target_table) }

    let(:target_table) { "users" }

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
        type: "string", sql_type: "varchar(255)", max_length: 255, limit: nil, nullable: false
      )
    end

    it "gives the size in bytes of an integer column as limit" do
      expect(column_named(schema, "age")).to have_attributes(type: "integer", limit: 2, max_length: nil, nullable: true)
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

    it "offers the timestamps for mapping" do
      expect(schema.columns.select { |target_column| target_column.name.end_with?("_at") }).to all(have_attributes(type: "datetime"))
    end

    it "describes a foreign key with its association, parent table and whether a parent is required" do
      expect(column_named(schema, "company_id").foreign_key).to eq(
        Pipeforge::ForeignKey.new(association: "company", parent_table: "companies", required: true)
      )
    end

    it "gives no foreign key for a column that is not one" do
      expect(column_named(schema, "email").foreign_key).to be_nil
    end

    context "with a foreign key marked optional" do
      let(:target_table) { "contacts" }

      it "does not require a parent" do
        expect(column_named(schema, "company_id").foreign_key.required).to be(false)
      end
    end

    context "with a foreign key and the model's own setting off" do
      let(:target_table) { "leads" }

      it "does not require a parent" do
        expect(column_named(schema, "company_id").foreign_key.required).to be(false)
      end
    end

    context "with a polymorphic association" do
      let(:target_table) { "comments" }

      it "does not describe its column as a foreign key" do
        expect(column_named(schema, "commentable_id").foreign_key).to be_nil
      end
    end

    context "with a composite foreign key" do
      let(:target_table) { "order_lines" }

      it "does not describe its columns as foreign keys" do
        expect(schema.columns.map(&:foreign_key)).to all(be_nil)
      end
    end

    context "with a composite primary key" do
      let(:target_table) { "orders" }

      it "leaves out every column of the key" do
        expect(schema.columns).to be_empty
      end
    end

    context "with single table inheritance" do
      let(:target_table) { "vehicles" }

      it "reads the table through the base class" do
        expect(schema.model).to eq("AdapterSpecModels::Vehicle")
      end
    end

    context "with two unrelated models on one table" do
      let(:target_table) { "notes" }

      it "uses the model whose class name comes first" do
        expect(schema.model).to eq("AdapterSpecModels::Memo")
      end
    end

    context "when the table does not exist" do
      let(:target_table) { "missing" }

      it "stops with target_table_not_found and the table" do
        expect { schema }.to raise_error(Pipeforge::TargetSchemaError) do |error|
          expect(error.errors.first).to include(code: :target_table_not_found, table: "missing")
        end
      end
    end

    context "when no model uses the table" do
      let(:target_table) { "orphans" }

      it "stops with active_record_model_not_found and the table" do
        expect { schema }.to raise_error(Pipeforge::TargetSchemaError) do |error|
          expect(error.errors.first).to include(code: :active_record_model_not_found, table: "orphans")
        end
      end
    end

    it "reads no row of the table, only its structure" do
      statement_names = []
      subscription = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        statement_names << payload[:name]
      end

      adapter.schema(target_table: "users")
      ActiveSupport::Notifications.unsubscribe(subscription)

      expect(statement_names.uniq).to eq(["SCHEMA"])
    end
  end

  describe "the core's target adapter" do
    it "is this adapter, once the gem is loaded" do
      expect(Pipeforge::TargetAdapter.schema(target_table: "users").model).to eq("AdapterSpecModels::User")
    end
  end
end
