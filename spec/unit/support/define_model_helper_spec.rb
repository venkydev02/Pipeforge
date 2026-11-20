# frozen_string_literal: true

# The spec helper define_model creates a real table and a real model for one example. These examples show that the
# model reads the table it was given, that a later example can use the same name with other columns, and that the
# options of the table reach it.
RSpec.describe DefineModelHelper do
  describe "#define_model" do
    it "gives a model named for the fact it shows" do
      model = define_model(name: "ModelWithOneColumn", columns: ->(table) { table.string :label })

      expect(model.name).to eq("AdapterSpecModels::ModelWithOneColumn")
    end

    it "gives a model whose table is named like it, with the columns declared and the usual id" do
      model = define_model(name: "ModelWithOneColumn", columns: ->(table) { table.string :label })

      expect([model.table_name, model.columns_hash.keys, model.primary_key]).to eq(
        ["model_with_one_column", %w[id label], "id"]
      )
    end

    # The two examples below use one name with other columns; whichever runs second would see the columns of the
    # first if the table were not dropped, or if ActiveRecord kept its columns.
    it "gives the columns of this example, the first time a name is used" do
      model = define_model(name: "ModelWithSharedName", columns: ->(table) { table.string :first_column })

      expect(model.columns_hash.keys).to eq(%w[id first_column])
    end

    it "gives the columns of this example, whichever example used the name before" do
      model = define_model(name: "ModelWithSharedName", columns: ->(table) { table.integer :second_column })

      expect(model.columns_hash.keys).to eq(%w[id second_column])
    end

    context "with primary_key false" do
      it "gives a table with no primary key" do
        model = define_model(name: "ModelWithoutKey", primary_key: false, columns: ->(table) { table.string :label })

        expect([model.primary_key, model.columns_hash.keys]).to eq([nil, %w[label]])
      end
    end

    context "with the names of a composite key" do
      it "gives a table with that composite primary key" do
        model = define_model(
          name: "ModelWithTwoKeyColumns", primary_key: [:shop_id, :number],
          columns: ->(table) {
            table.integer :shop_id
            table.integer :number
          }
        )

        expect(model.primary_key).to eq(%w[shop_id number])
      end
    end

    context "with a block" do
      it "runs it as the body of the model class" do
        model = define_model(name: "ModelWithAttribute", columns: ->(table) { table.string :label }) do
          attribute :label, :string, default: "none"
        end

        expect(model.new.label).to eq("none")
      end
    end

    context "when no columns are given" do
      it "gives a table with only the usual id" do
        model = define_model(name: "ModelWithNoColumns")

        expect(model.columns_hash.keys).to eq(%w[id])
      end
    end
  end
end
