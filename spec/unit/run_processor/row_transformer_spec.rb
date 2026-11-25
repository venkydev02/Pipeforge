# frozen_string_literal: true

# Each mapped column has a source column name that differs from its target column name, so a cell read from the wrong
# column shows.
RSpec.describe Pipeforge::RunProcessor::RowTransformer do
  def transformer_of(mapped_columns:)
    described_class.new(resolved_mapped_columns: resolve_mapped_columns(mapped_columns))
  end

  describe ".new" do
    context "when resolved_mapped_columns has a mapped column" do
      let(:mapped_columns_with_one_column) { {"email" => {source_column_name: "Mail"}} }

      it "gives a transformer that answers result_of_row" do
        expect(transformer_of(mapped_columns: mapped_columns_with_one_column)).to respond_to(:result_of_row)
      end
    end

    context "when resolved_mapped_columns is empty" do
      subject(:values) { transformer_of(mapped_columns: {}).result_of_row(row: row_with_a_cell) }

      let(:row_with_a_cell) { {"Mail" => "ann@example.com"} }

      it "gives no value for any row" do
        expect(values).to eq({})
      end
    end
  end

  describe "#result_of_row" do
    describe "reading the cells" do
      context "when the row is a Hash of source column name => text" do
        subject(:values) { transformer_of(mapped_columns: mapped_columns_of_one_column).result_of_row(row: row_with_a_mail) }

        let(:mapped_columns_of_one_column) { {"email" => {source_column_name: "Mail"}} }
        let(:row_with_a_mail) { {"Mail" => "ann@example.com"} }

        it "gives a Hash of target column name => value" do
          expect(values).to eq("email" => "ann@example.com")
        end
      end

      context "when two mapped columns read source columns of another name" do
        subject(:values) { transformer_of(mapped_columns: mapped_columns_of_two_columns).result_of_row(row: row_with_two_cells) }

        let(:mapped_columns_of_two_columns) do
          {
            "email" => {source_column_name: "Mail"},
            "name" => {source_column_name: "Full name"}
          }
        end
        let(:row_with_two_cells) { {"Mail" => "ann@example.com", "Full name" => "Ann"} }

        it "gives each target column the cell of its own source column" do
          expect(values).to eq("email" => "ann@example.com", "name" => "Ann")
        end
      end

      context "when the row has a source column that no mapped column reads" do
        subject(:values) { transformer_of(mapped_columns: mapped_columns_of_one_column).result_of_row(row: row_with_an_unread_column) }

        let(:mapped_columns_of_one_column) { {"email" => {source_column_name: "Mail"}} }
        let(:row_with_an_unread_column) { {"Mail" => "ann@example.com", "Zip" => "10001"} }

        it "leaves that source column out of the result" do
          expect(values).to eq("email" => "ann@example.com")
        end
      end

      context "when two target columns read the same source column" do
        subject(:values) { transformer_of(mapped_columns: mapped_columns_with_a_shared_source).result_of_row(row: row_with_a_name) }

        let(:mapped_columns_with_a_shared_source) do
          {
            "first_name" => {source_column_name: "Name"},
            "display_name" => {source_column_name: "Name"}
          }
        end
        let(:row_with_a_name) { {"Name" => "Ann"} }

        it "gives both of them its value" do
          expect(values).to eq("first_name" => "Ann", "display_name" => "Ann")
        end
      end

      context "when the source column of a mapped column is not in the row" do
        subject(:values) { transformer_of(mapped_columns: mapped_columns_of_two_columns).result_of_row(row: row_without_the_name) }

        let(:mapped_columns_of_two_columns) do
          {
            "email" => {source_column_name: "Mail"},
            "name" => {source_column_name: "Full name"}
          }
        end
        let(:row_without_the_name) { {"Mail" => "ann@example.com"} }

        it "leaves that target column out of the result" do
          expect(values).to eq("email" => "ann@example.com")
        end
      end

      context "when the row is empty" do
        subject(:values) { transformer_of(mapped_columns: mapped_columns_of_one_column).result_of_row(row: empty_row) }

        let(:mapped_columns_of_one_column) { {"email" => {source_column_name: "Mail"}} }
        let(:empty_row) { {} }

        it "gives an empty Hash" do
          expect(values).to eq({})
        end
      end
    end

    describe "a blank cell" do
      subject(:values) { transformer_of(mapped_columns: mapped_columns_of_two_columns).result_of_row(row: row_with_a_blank_mail) }

      let(:mapped_columns_of_two_columns) do
        {
          "email" => {source_column_name: "Mail"},
          "name" => {source_column_name: "Full name"}
        }
      end

      context "when the cell is nil" do
        let(:row_with_a_blank_mail) { {"Mail" => nil, "Full name" => "Ann"} }

        it "leaves the column out" do
          expect(values).to eq("name" => "Ann")
        end
      end

      context "when the cell is a text with nothing but whitespace" do
        let(:row_with_a_blank_mail) { {"Mail" => " \t ", "Full name" => "Ann"} }

        it "leaves the column out" do
          expect(values).to eq("name" => "Ann")
        end
      end

      context "when the cell is the empty text" do
        let(:row_with_a_blank_mail) { {"Mail" => "", "Full name" => "Ann"} }

        it "leaves the column out" do
          expect(values).to eq("name" => "Ann")
        end
      end
    end

    describe "the value mapping" do
      subject(:values) { transformer_of(mapped_columns: mapped_columns_with_a_value_mapping).result_of_row(row: row_with_a_status) }

      context "when the cell is a key of the value mapping" do
        let(:mapped_columns_with_a_value_mapping) do
          {"status" => {source_column_name: "State", value_mapping: {"Y" => "active"}}}
        end
        let(:row_with_a_status) { {"State" => "Y"} }

        it "gives the column the mapped value" do
          expect(values).to eq("status" => "active")
        end
      end

      context "when the cell is not a key of the value mapping" do
        let(:mapped_columns_with_a_value_mapping) do
          {"status" => {source_column_name: "State", value_mapping: {"Y" => "active"}}}
        end
        let(:row_with_a_status) { {"State" => "pending"} }

        it "gives the column the cell as it is" do
          expect(values).to eq("status" => "pending")
        end
      end

      context "when the cell maps to nil" do
        let(:mapped_columns_with_a_value_mapping) do
          {"status" => {source_column_name: "State", value_mapping: {"n/a" => nil}}}
        end
        let(:row_with_a_status) { {"State" => "n/a"} }

        it "leaves the column out" do
          expect(values).to eq({})
        end
      end

      context "when the cell maps to a text with nothing but whitespace" do
        let(:mapped_columns_with_a_value_mapping) do
          {"status" => {source_column_name: "State", value_mapping: {"n/a" => "  "}}}
        end
        let(:row_with_a_status) { {"State" => "n/a"} }

        it "leaves the column out" do
          expect(values).to eq({})
        end
      end

      context "when the cell maps to false" do
        let(:mapped_columns_with_a_value_mapping) do
          {"status" => {source_column_name: "State", value_mapping: {"no" => false}}}
        end
        let(:row_with_a_status) { {"State" => "no"} }

        it "gives the column false" do
          expect(values).to eq("status" => false)
        end
      end

      context "when the cell maps to 0" do
        let(:mapped_columns_with_a_value_mapping) do
          {"status" => {source_column_name: "State", value_mapping: {"none" => 0}}}
        end
        let(:row_with_a_status) { {"State" => "none"} }

        it "gives the column 0" do
          expect(values).to eq("status" => 0)
        end
      end

      context "when a key of the value mapping differs from the cell only by whitespace" do
        let(:mapped_columns_with_a_value_mapping) do
          {"status" => {source_column_name: "State", value_mapping: {"Y " => "active"}}}
        end
        let(:row_with_a_status) { {"State" => "Y"} }

        it "does not match the key and gives the column the cell as it is" do
          expect(values).to eq("status" => "Y")
        end
      end

      context "when the cell is blank and the value mapping has that cell as a key, mapped to a text" do
        let(:mapped_columns_with_a_value_mapping) do
          {"status" => {source_column_name: "State", value_mapping: {"  " => "unknown"}}}
        end
        let(:row_with_a_status) { {"State" => "  "} }

        it "gives the column the mapped text" do
          expect(values).to eq("status" => "unknown")
        end
      end
    end

    context "when the mapped columns are in one order and the row lists its source columns in another" do
      subject(:values) { transformer_of(mapped_columns: mapped_columns_in_order).result_of_row(row: row_in_another_order) }

      let(:mapped_columns_in_order) do
        {
          "name" => {source_column_name: "Full name"},
          "email" => {source_column_name: "Mail"},
          "age" => {source_column_name: "Years"}
        }
      end
      let(:row_in_another_order) { {"Years" => "30", "Mail" => "ann@example.com", "Full name" => "Ann"} }

      it "lists the target columns in the order of the mapped columns" do
        expect(values.to_a).to eq([["name", "Ann"], ["email", "ann@example.com"], ["age", "30"]])
      end
    end

    context "when the row and the value mapping are given" do
      subject(:values) { transformer_of(mapped_columns: mapped_columns_with_a_value_mapping).result_of_row(row: row_given_to_the_transformer) }

      let(:mapped_columns_with_a_value_mapping) do
        {
          "status" => {source_column_name: "State", value_mapping: {"Y" => "active", "n/a" => nil}},
          "email" => {source_column_name: "Mail"}
        }
      end
      let(:row_given_to_the_transformer) { {"State" => "n/a", "Mail" => "", "Zip" => "10001"} }

      it "does not change the row" do
        expect { values }.not_to change { row_given_to_the_transformer.dup }
      end

      it "does not change the value mapping" do
        resolved_mapped_columns = resolve_mapped_columns(mapped_columns_with_a_value_mapping)
        value_mapping_before = resolved_mapped_columns["status"].value_mapping.dup
        described_class.new(resolved_mapped_columns: resolved_mapped_columns)
          .result_of_row(row: row_given_to_the_transformer)

        expect(resolved_mapped_columns["status"].value_mapping).to eq(value_mapping_before)
      end
    end

    context "when one transformer is used for two rows, the first with values and the second empty" do
      let(:transformer_of_one_column) { transformer_of(mapped_columns: {"email" => {source_column_name: "Mail"}}) }
      let(:row_with_a_mail) { {"Mail" => "ann@example.com"} }
      let(:row_with_an_empty_mail) { {"Mail" => nil} }

      it "gives the second row nothing from the first" do
        transformer_of_one_column.result_of_row(row: row_with_a_mail)

        expect(transformer_of_one_column.result_of_row(row: row_with_an_empty_mail)).to eq({})
      end
    end

    describe "collaboration with Utilities.blank?" do
      subject(:values) { transformer_of(mapped_columns: mapped_columns_with_a_value_mapping).result_of_row(row: row_with_a_status) }

      before { allow(Pipeforge::Utilities).to receive(:blank?).and_call_original }

      let(:mapped_columns_with_a_value_mapping) do
        {"status" => {source_column_name: "State", value_mapping: {"n/a" => nil, "no" => false}}}
      end

      context "when the cell maps to nil" do
        let(:row_with_a_status) { {"State" => "n/a"} }

        it "asks Utilities.blank? about the mapped value and not about the cell" do
          values

          expect(Pipeforge::Utilities).to have_received(:blank?).with(value: nil)
          expect(Pipeforge::Utilities).not_to have_received(:blank?).with(value: "n/a")
        end

        it "leaves the column out" do
          expect(values).to eq({})
        end
      end

      context "when the cell maps to false" do
        let(:row_with_a_status) { {"State" => "no"} }

        it "asks Utilities.blank? about the mapped value and not about the cell" do
          values

          expect(Pipeforge::Utilities).to have_received(:blank?).with(value: false)
          expect(Pipeforge::Utilities).not_to have_received(:blank?).with(value: "no")
        end

        it "keeps the column with false" do
          expect(values).to eq("status" => false)
        end
      end
    end
  end
end
