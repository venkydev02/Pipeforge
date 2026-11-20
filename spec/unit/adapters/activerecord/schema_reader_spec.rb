# frozen_string_literal: true

# The reader translates what ActiveRecord reports about a model, and ActiveRecord is a third-party gem, so every
# example reads a real model over a real table of the PostgreSQL test database, made by define_model in the example
# and dropped after it, and nothing is replaced by a double: a change in a new version of ActiveRecord shows here.
# The models are named for the fact they show. The parents AdapterSpecModels::Company and AdapterSpecModels::Order
# are the only models taken from spec/support/active_record_helper.rb.
# An example that no break fails alone is kept for what the rule accepts or reports (contract only).
RSpec.describe Pipeforge::ActiveRecordSchemaReader do
  subject(:schema) do
    described_class.new(model: model, enum_labels: enum_labels, polymorphic_columns: polymorphic_columns).call
  end

  let(:enum_labels) { {} }
  let(:polymorphic_columns) { {} }
  let(:target_column) do
    schema.columns.find { |column| column.name == column_name }
  end

  def define_model_with_typed_columns
    define_model(
      name: "ModelWithTypedColumns",
      columns: lambda do |table|
        table.string :email, limit: 255, null: false
        table.integer :age, limit: 2
        table.decimal :balance, precision: 10, scale: 2
        table.text :bio
        table.boolean :active, default: true
        table.timestamps null: false
      end
    )
  end

  def define_model_with_floats
    define_model(
      name: "ModelWithFloats",
      columns: lambda do |table|
        table.float :ratio, limit: 24
        table.float :weight
      end
    )
  end

  def define_model_with_model_default
    define_model(name: "ModelWithModelDefault", columns: ->(table) { table.string :channel, null: false }) do
      attribute :channel, :string, default: "web"
    end
  end

  def define_model_with_required_columns
    define_model(
      name: "ModelWithRequiredColumns",
      columns: lambda do |table|
        table.string :number, null: false
        table.string :status, null: false, default: "open"
        table.datetime :issued_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
        table.timestamps null: false
      end
    )
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

  describe "#call" do
    describe "the schema" do
      context "when model is ModelWithTypedColumns" do
        let(:model) { define_model_with_typed_columns }

        # contract only
        it "has table_name \"model_with_typed_columns\" and model_name \"AdapterSpecModels::ModelWithTypedColumns\"" do
          expect(schema.table_name).to eq("model_with_typed_columns")
          expect(schema.model_name).to eq("AdapterSpecModels::ModelWithTypedColumns")
        end

        it "has the columns in the order of the model" do
          expect(schema.columns.map(&:name)).to eq(%w[email age balance bio active created_at updated_at])
        end

        # contract only
        it "has a TargetColumn for each column" do
          expect(schema.columns).to all(be_a(Pipeforge::TargetColumn))
        end
      end
    end

    describe "the columns that are in the schema" do
      context "when model is ModelWithTypedColumns, whose primary_key is \"id\"" do
        let(:model) { define_model_with_typed_columns }

        # contract only
        it "leaves out id and has email" do
          names = schema.columns.map(&:name)

          expect(names).to include("email")
          expect(names).not_to include("id")
        end
      end

      context "when model is ModelWithCompositePrimaryKey, whose primary_key is shop_id and number" do
        let(:model) do
          define_model(
            name: "ModelWithCompositePrimaryKey", primary_key: [:shop_id, :number],
            columns: lambda do |table|
              table.integer :shop_id
              table.integer :number
            end
          )
        end

        it "has no column" do
          expect(schema.columns).to be_empty
        end
      end

      context "when model is ModelWithoutPrimaryKey, whose table has no primary key" do
        let(:model) do
          define_model(name: "ModelWithoutPrimaryKey", primary_key: false, columns: ->(table) { table.string :label })
        end

        # contract only
        it "has label" do
          expect(schema.columns.map(&:name)).to eq(%w[label])
        end
      end

      context "when model is ModelWithGeneratedColumn, which has the generated column shout" do
        let(:model) do
          define_model(
            name: "ModelWithGeneratedColumn",
            columns: lambda do |table|
              table.string :email
              table.virtual :shout, type: :string, as: "upper(email)", stored: false
            end
          )
        end

        it "leaves out shout and has email" do
          names = schema.columns.map(&:name)

          expect(names).to include("email")
          expect(names).not_to include("shout")
        end
      end

      context "when model is ModelWithArrayColumns, which has the array columns track_ids and tags" do
        let(:model) do
          define_model(
            name: "ModelWithArrayColumns",
            columns: lambda do |table|
              table.string :title
              table.column :track_ids, :integer, array: true
              table.column :tags, :text, array: true
            end
          )
        end

        # contract only
        it "has only title" do
          expect(schema.columns.map(&:name)).to eq(%w[title])
        end
      end
    end

    describe "the type and size fields" do
      context "when column is email of ModelWithTypedColumns" do
        let(:model) { define_model_with_typed_columns }
        let(:column_name) { "email" }

        # contract only
        it "has name \"email\", type \"string\", sql_type \"character varying(255)\" and max_length 255, with limit nil" do
          expect(target_column).to have_attributes(
            name: "email", type: "string", sql_type: "character varying(255)", max_length: 255, limit: nil
          )
        end
      end

      context "when column is bio of ModelWithTextLimit, a text attribute with limit 100" do
        let(:model) do
          define_model(name: "ModelWithTextLimit", columns: ->(table) { table.text :bio }) do
            attribute :bio, :text, limit: 100
          end
        end
        let(:column_name) { "bio" }

        it "has type \"text\" and max_length 100, with limit nil" do
          expect(target_column).to have_attributes(type: "text", max_length: 100, limit: nil)
        end
      end

      context "when column is bio of ModelWithTypedColumns" do
        let(:model) { define_model_with_typed_columns }
        let(:column_name) { "bio" }

        # contract only
        it "has type \"text\", with max_length and limit nil" do
          expect(target_column).to have_attributes(type: "text", max_length: nil, limit: nil)
        end
      end

      context "when column is age of ModelWithTypedColumns" do
        let(:model) { define_model_with_typed_columns }
        let(:column_name) { "age" }

        # contract only
        it "has type \"integer\", sql_type \"smallint\" and limit 2, with max_length nil" do
          expect(target_column).to have_attributes(type: "integer", sql_type: "smallint", limit: 2, max_length: nil)
        end
      end

      context "when column is ratio of ModelWithFloats" do
        let(:model) { define_model_with_floats }
        let(:column_name) { "ratio" }

        # contract only
        it "has type \"float\" and limit 24" do
          expect(target_column).to have_attributes(type: "float", limit: 24)
        end
      end

      context "when column is weight of ModelWithFloats" do
        let(:model) { define_model_with_floats }
        let(:column_name) { "weight" }

        # contract only
        it "has type \"float\", with limit nil" do
          expect(target_column).to have_attributes(type: "float", limit: nil)
        end
      end

      context "when column is balance of ModelWithTypedColumns" do
        let(:model) { define_model_with_typed_columns }
        let(:column_name) { "balance" }

        # contract only
        it "has type \"decimal\", precision 10 and scale 2" do
          expect(target_column).to have_attributes(type: "decimal", precision: 10, scale: 2)
        end
      end

      context "when column is active of ModelWithTypedColumns" do
        let(:model) { define_model_with_typed_columns }
        let(:column_name) { "active" }

        # contract only
        it "has type \"boolean\", with limit, max_length, precision and scale nil" do
          expect(target_column).to have_attributes(
            type: "boolean", limit: nil, max_length: nil, precision: nil, scale: nil
          )
        end
      end
    end

    describe "is_signed" do
      context "when column is age of ModelWithTypedColumns" do
        let(:model) { define_model_with_typed_columns }
        let(:column_name) { "age" }

        # contract only
        it "is true" do
          expect(target_column.is_signed).to be(true)
        end
      end

      context "when column is hits of ModelWithUnsignedInteger, an unsigned integer attribute" do
        let(:model) do
          define_model(name: "ModelWithUnsignedInteger", columns: ->(table) { table.integer :hits }) do
            attribute :hits, ActiveRecord::Type::UnsignedInteger.new(limit: 2)
          end
        end
        let(:column_name) { "hits" }

        it "is false, with type \"integer\" and limit 2" do
          expect(target_column).to have_attributes(is_signed: false, type: "integer", limit: 2)
        end
      end

      context "when column is email of ModelWithTypedColumns" do
        let(:model) { define_model_with_typed_columns }
        let(:column_name) { "email" }

        it "is nil" do
          expect(target_column.is_signed).to be_nil
        end
      end
    end

    describe "default, enum_labels and polymorphic" do
      context "when column is active of ModelWithTypedColumns, which the table defaults to true" do
        let(:model) { define_model_with_typed_columns }
        let(:column_name) { "active" }

        # contract only
        it "has default true" do
          expect(target_column.default).to be(true)
        end
      end

      context "when column is channel of ModelWithModelDefault, whose default is set only in the model" do
        let(:model) { define_model_with_model_default }
        let(:column_name) { "channel" }

        it "has default \"web\"" do
          expect(target_column.default).to eq("web")
        end
      end

      context "when column is email of ModelWithTypedColumns, which has no default" do
        let(:model) { define_model_with_typed_columns }
        let(:column_name) { "email" }

        # contract only
        it "has default nil" do
          expect(target_column.default).to be_nil
        end
      end

      context "when model is ModelWithEnum and enum_labels is {\"status\" => [\"draft\", \"placed\", \"shipped\"]}" do
        let(:model) do
          define_model(
            name: "ModelWithEnum",
            columns: lambda do |table|
              table.integer :status, null: false, default: 0
              table.string :kind
            end
          ) do
            enum :status, {draft: 0, placed: 1, shipped: 2}
          end
        end
        let(:enum_labels) { {"status" => %w[draft placed shipped]} }

        it "has those enum_labels on status" do
          status_column = schema.columns.find { |column| column.name == "status" }

          expect(status_column.enum_labels).to eq(%w[draft placed shipped])
        end

        # contract only
        it "has enum_labels nil on kind" do
          kind_column = schema.columns.find { |column| column.name == "kind" }

          expect(kind_column.enum_labels).to be_nil
        end
      end

      context "when model is ModelWithPolymorphicParent" do
        let(:model) { define_model_with_polymorphic_parent }

        context "and polymorphic_columns has commentable_id with role \"id\" and commentable_type with role \"type\"" do
          let(:polymorphic_columns) do
            {
              "commentable_id" => Pipeforge::PolymorphicColumn.new(association_name: "commentable", role: "id"),
              "commentable_type" => Pipeforge::PolymorphicColumn.new(association_name: "commentable", role: "type")
            }
          end

          it "has its PolymorphicColumn on each of the two columns" do
            polymorphic_by_name = schema.columns.to_h { |column| [column.name, column.polymorphic] }

            expect(polymorphic_by_name).to eq(polymorphic_columns)
          end
        end

        context "and polymorphic_columns is empty" do
          # contract only
          it "has polymorphic nil on both columns" do
            expect(schema.columns.map(&:polymorphic)).to eq([nil, nil])
          end
        end
      end
    end

    describe "required" do
      context "when column is age of ModelWithTypedColumns, which accepts an empty value" do
        let(:model) { define_model_with_typed_columns }
        let(:column_name) { "age" }

        it "is false" do
          expect(target_column.required).to be(false)
        end
      end

      context "when model is ModelWithRequiredColumns" do
        let(:model) { define_model_with_required_columns }

        context "and column is status, which is NOT NULL with a value default" do
          let(:column_name) { "status" }

          # contract only
          it "is false" do
            expect(target_column.required).to be(false)
          end
        end

        context "and column is issued_at, which is NOT NULL with a function default" do
          let(:column_name) { "issued_at" }

          it "is false" do
            expect(target_column.required).to be(false)
          end
        end

        context "and column is number, which is NOT NULL with no default and is not a timestamp" do
          let(:column_name) { "number" }

          # contract only
          it "is true" do
            expect(target_column.required).to be(true)
          end
        end
      end

      context "when column is channel of ModelWithModelDefault, which is NOT NULL with a default set in the model" do
        let(:model) { define_model_with_model_default }
        let(:column_name) { "channel" }

        it "is false" do
          expect(target_column.required).to be(false)
        end
      end

      context "when column is created_at of ModelWithTypedColumns, which is NOT NULL with no default" do
        let(:model) { define_model_with_typed_columns }
        let(:column_name) { "created_at" }

        # The model records timestamps, so it fills the column when it saves.
        it "is false" do
          expect(target_column.required).to be(false)
        end
      end

      context "when column is created_at of ModelWithoutTimestampRecording, which is NOT NULL with no default" do
        let(:model) do
          define_model(
            name: "ModelWithoutTimestampRecording",
            columns: lambda do |table|
              table.string :number, null: false
              table.timestamps null: false
            end
          ) do
            self.record_timestamps = false
          end
        end
        let(:column_name) { "created_at" }

        # Nothing fills the column when the model does not record timestamps.
        it "is true" do
          expect(target_column.required).to be(true)
        end
      end
    end

    describe "foreign_key" do
      context "when model is ModelWithParent, with belongs_to :company" do
        let(:model) do
          define_model(
            name: "ModelWithParent",
            columns: lambda do |table|
              table.string :email
              table.bigint :company_id
            end
          ) do
            belongs_to :company, class_name: "AdapterSpecModels::Company"
          end
        end

        context "and column is company_id" do
          let(:column_name) { "company_id" }

          it "has association_name \"company\" and parent_table_name \"companies\"" do
            expect(target_column.foreign_key).to eq(
              Pipeforge::ForeignKey.new(association_name: "company", parent_table_name: "companies")
            )
          end
        end

        context "and column is email, which no association uses" do
          let(:column_name) { "email" }

          # contract only
          it "has foreign_key nil" do
            expect(target_column.foreign_key).to be_nil
          end
        end
      end

      context "when model is ModelWithTwoParents, with belongs_to on from_company_id and to_company_id" do
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

        # contract only
        it "has its own foreign_key, with its own association_name, on each column" do
          foreign_keys_by_column_name = schema.columns.to_h { |column| [column.name, column.foreign_key] }

          expect(foreign_keys_by_column_name).to eq(
            "from_company_id" => Pipeforge::ForeignKey.new(association_name: "from_company", parent_table_name: "companies"),
            "to_company_id" => Pipeforge::ForeignKey.new(association_name: "to_company", parent_table_name: "companies")
          )
        end
      end

      context "when column is commentable_id of ModelWithPolymorphicParent, a polymorphic belongs_to" do
        let(:model) { define_model_with_polymorphic_parent }
        let(:column_name) { "commentable_id" }

        # contract only
        it "has foreign_key nil" do
          expect(target_column.foreign_key).to be_nil
        end
      end

      context "when model is ModelWithCompositeParent, whose belongs_to has the composite foreign key shop_id and order_number" do
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

        # contract only
        it "has foreign_key nil on each column" do
          expect(schema.columns.map(&:foreign_key)).to eq([nil, nil])
        end
      end
    end
  end
end
