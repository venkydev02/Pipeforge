# frozen_string_literal: true

# The spec helpers queries_on and statement_names read the statements that ActiveRecord sends while a block runs. The
# examples run real statements on small real tables made with define_model.
RSpec.describe SqlStatementsHelper do
  let(:model) { define_model(name: "ModelWithRows", columns: ->(table) { table.string :label }) }
  let(:other_model) { define_model(name: "ModelWithOtherRows", columns: ->(table) { table.string :label }) }

  describe "#queries_on" do
    it "gives the statement that a block sends to the table" do
      model
      statements = queries_on("model_with_rows") { model.count }

      expect(statements.size).to eq(1)
    end

    it "names the table in the statement it gives" do
      model
      statements = queries_on("model_with_rows") { model.count }

      expect(statements.first).to include('"model_with_rows"')
    end

    it "gives nothing for a statement that names another table" do
      model
      other_model

      expect(queries_on("model_with_rows") { other_model.count }).to eq([])
    end

    it "gives every statement the block sends to the table, in the order sent" do
      model
      statements = queries_on("model_with_rows") do
        model.create!(label: "a")
        model.count
      end

      expect(statements.map { |statement| statement.split.first }).to eq(%w[INSERT SELECT])
    end

    it "leaves out the reads of the structure of the table" do
      model.reset_column_information
      statements = queries_on("model_with_rows") { model.columns_hash }

      expect(statements).to eq([])
    end

    it "gives nothing for a block that sends no statement" do
      expect(queries_on("model_with_rows") { 1 + 1 }).to eq([])
    end

    it "stops listening when the block ends" do
      model
      queries_on("model_with_rows") { model.count }

      expect(queries_on("model_with_rows") { 1 + 1 }).to eq([])
    end

    it "stops listening when the block raises, and raises the error" do
      model
      expect { queries_on("model_with_rows") { raise "stop" } }.to raise_error(RuntimeError, "stop")

      expect(ActiveSupport::Notifications.notifier.listening?("sql.active_record")).to be(false)
    end
  end

  describe "#statement_names" do
    it "gives the label of the statement that a block sends" do
      model

      expect(statement_names { model.count }).to eq(["AdapterSpecModels::ModelWithRows Count"])
    end

    it "gives the label SCHEMA for a read of the structure of a table" do
      model.reset_column_information

      expect(statement_names { model.columns_hash }.uniq).to eq(["SCHEMA"])
    end

    it "gives nothing for a block that sends no statement" do
      expect(statement_names { 1 + 1 }).to eq([])
    end
  end
end
