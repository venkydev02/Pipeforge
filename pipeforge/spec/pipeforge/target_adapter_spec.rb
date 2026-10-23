# frozen_string_literal: true

RSpec.describe Pipeforge::TargetAdapter do
  let(:schema) { build_target_schema(table_name: "records", model: nil, columns: []) }
  let(:adapter) { double("target adapter", schema: schema) }

  # The adapter is kept by the module itself, so each example leaves none installed.
  before { described_class.install(adapter: nil) }

  after { described_class.install(adapter: nil) }

  describe ".ensure_installed" do
    it "does nothing when an adapter is installed" do
      described_class.install(adapter: adapter)

      expect { described_class.ensure_installed }.not_to raise_error
    end

    it "stops with target_adapter_not_installed when no adapter is installed" do
      expect { described_class.ensure_installed }.to raise_error(Pipeforge::TargetAdapterError) do |error|
        expect(error.codes).to eq([:target_adapter_not_installed])
      end
    end
  end

  describe ".schema" do
    context "when an adapter is installed" do
      before { described_class.install(adapter: adapter) }

      it "gives the schema the adapter returns" do
        expect(described_class.schema(target_table: "records")).to eq(schema)
      end

      it "asks the adapter for the table it was given" do
        described_class.schema(target_table: "records")

        expect(adapter).to have_received(:schema).with(target_table: "records")
      end
    end

    context "when no adapter is installed" do
      it "stops with target_adapter_not_installed" do
        expect { described_class.schema(target_table: "records") }.to raise_error(Pipeforge::TargetAdapterError) do |error|
          expect(error.codes).to eq([:target_adapter_not_installed])
        end
      end
    end

    context "when a second adapter is installed" do
      let(:second_schema) { build_target_schema(table_name: "records", model: "Second", columns: []) }

      before do
        described_class.install(adapter: adapter)
        described_class.install(adapter: double("second adapter", schema: second_schema))
      end

      it "uses the last one installed" do
        expect(described_class.schema(target_table: "records")).to eq(second_schema)
      end
    end
  end
end
