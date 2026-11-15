# frozen_string_literal: true

RSpec.describe Pipeforge::MappedColumn do
  describe ".from_entry" do
    subject(:mapped_column) { described_class.from_entry(entry: entry, target_column: target_column) }

    let(:target_column) { build_target_column(name: "email") }
    let(:entry) { {source_column: "Mail"} }

    it "keeps the source column" do
      expect(mapped_column.source_column).to eq("Mail")
    end

    it "gives the target column it was given" do
      expect(mapped_column.target_column).to be(target_column)
    end

    context "when the entry has no value mapping" do
      it "has an empty value mapping" do
        expect(mapped_column.value_mapping).to eq({})
      end
    end

    context "when the entry has a value mapping" do
      let(:entry) { {source_column: "Mail", value_mapping: {"N/A" => nil, "ann" => "Ann"}} }

      it "keeps it" do
        expect(mapped_column.value_mapping).to eq("N/A" => nil, "ann" => "Ann")
      end
    end

    context "when a key of the value mapping is not text" do
      let(:entry) { {source_column: "Level", value_mapping: {1 => "one", 3 => "tre"}} }

      it "turns the keys into text" do
        expect(mapped_column.value_mapping).to eq("1" => "one", "3" => "tre")
      end

      it "leaves the value mapping of the entry as it was written" do
        mapped_column

        expect(entry[:value_mapping]).to eq({1 => "one", 3 => "tre"})
      end
    end

    context "when two keys give the same text" do
      let(:entry) { {source_column: "Level", value_mapping: {1 => "x", "1" => "20"}} }

      it "makes them one key, and the later one is used" do
        expect(mapped_column.value_mapping).to eq("1" => "20")
      end
    end

    context "when the entry has no source column" do
      let(:entry) { {value_mapping: {}} }

      it "raises a KeyError" do
        expect { mapped_column }.to raise_error(KeyError)
      end
    end
  end
end
