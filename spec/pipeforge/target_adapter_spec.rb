# frozen_string_literal: true

RSpec.describe Pipeforge::TargetAdapter do
  let(:schema) { build_target_schema(table_name: "records", model: nil, columns: []) }
  let(:adapter) { double("target adapter", schema: schema) }

  # The adapter is kept by the module itself, so each example runs with none installed and the real one is put back.
  around { |example| without_installed_adapter { example.run } }

  describe ".schema" do
    context "when an adapter is installed" do
      before { described_class.install(adapter: adapter) }

      it "gives the schema the adapter returns" do
        expect(described_class.schema(target_model: "Record")).to eq(schema)
      end

      it "asks the adapter for the table it was given" do
        described_class.schema(target_model: "Record")

        expect(adapter).to have_received(:schema).with(target_model: "Record")
      end
    end

    context "when asked for the model adapter" do
      let(:model_adapter) { double("model adapter") }
      let(:adapter) { double("target adapter", schema: schema, model_adapter: model_adapter) }

      before { described_class.install(adapter: adapter) }

      it "gives the model adapter the installed adapter returns" do
        expect(described_class.model_adapter(target_model: "Record")).to be(model_adapter)
      end

      it "asks the adapter for the table it was given" do
        described_class.model_adapter(target_model: "Record")

        expect(adapter).to have_received(:model_adapter).with(target_model: "Record")
      end
    end

    context "when a second adapter is installed" do
      let(:second_schema) { build_target_schema(table_name: "records", model: "Second", columns: []) }

      before do
        described_class.install(adapter: adapter)
        described_class.install(adapter: double("second adapter", schema: second_schema))
      end

      it "uses the last one installed" do
        expect(described_class.schema(target_model: "Record")).to eq(second_schema)
      end
    end
  end
end
