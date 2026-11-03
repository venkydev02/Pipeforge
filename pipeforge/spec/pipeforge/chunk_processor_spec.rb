# frozen_string_literal: true

RSpec.describe Pipeforge::ChunkProcessor do
  describe ".call" do
    subject(:chunk_result) do
      described_class.call(
        rows: rows, first_row_number: 5, transformer: transformer, schema_checker: schema_checker,
        target_schema: target_schema, model_adapter: model_adapter
      )
    end

    let(:target_columns) do
      [
        build_target_column(name: "email", required: true),
        build_target_column(name: "status", max_length: 6)
      ]
    end
    let(:target_schema) { build_target_schema(columns: target_columns) }
    let(:mapped_columns) do
      {
        "email" => {source_column: "Mail"},
        "status" => {source_column: "State", value_mapping: {"ok" => "active"}}
      }
    end
    let(:transformer) { Pipeforge::RowTransformer.new(mapped_columns: mapped_columns) }
    let(:schema_checker) { Pipeforge::SchemaChecker.new(target_schema: target_schema) }
    let(:model_adapter) { FakeModelAdapter.new(errors_of: errors_of) }
    let(:errors_of) { ->(attributes:) { [] } }
    let(:rows) do
      [
        {"Mail" => "a@example.com", "State" => "ok"},
        {"Mail" => nil, "State" => "ok"},
        {"Mail" => "c@example.com", "State" => "far too long"}
      ]
    end

    it "returns a ChunkResult" do
      expect(chunk_result).to be_a(Pipeforge::ChunkResult)
    end

    it "numbers the rows from the first row number" do
      expect(chunk_result).to have_attributes(first_row_number: 5, last_row_number: 7)
    end

    it "counts the rows that were processed, valid and invalid" do
      expect(chunk_result).to have_attributes(processed_rows_count: 3, valid_rows_count: 1, failed_rows_count: 2)
    end

    it "lists a failed row for each row that did not pass, in file order, with its absolute row number" do
      expect(chunk_result.failed_rows.map(&:row_number)).to eq([6, 7])
    end

    it "gives each failed row the transformed values, after the value mapping" do
      expect(chunk_result.failed_rows.first.mapped_values).to eq("email" => nil, "status" => "active")
    end

    it "gives each failed row its errors with the origin" do
      expect(chunk_result.failed_rows.map { |failed_row| failed_row.errors.map { |error| [error[:code], error[:origin]] } }).to eq(
        [[[:value_missing, :schema]], [[:value_too_long, :schema]]]
      )
    end

    it "builds the record of each row from its transformed values" do
      chunk_result

      expect(model_adapter.built_attributes.first).to eq("email" => "a@example.com", "status" => "active")
    end

    it "preloads the parents once, for every record of the chunk" do
      chunk_result

      expect(model_adapter.preload_calls.map(&:size)).to eq([3])
    end

    it "preloads after every record is built" do
      allow(model_adapter).to receive(:preload_parents).and_wrap_original do |original, **arguments|
        expect(model_adapter.built_attributes.size).to eq(3)
        original.call(**arguments)
      end

      chunk_result
    end

    context "when the model finds a mistake in a row" do
      let(:rows) { [{"Mail" => "a@example.com", "State" => "ok"}, {"Mail" => "dup@example.com", "State" => "ok"}] }
      let(:errors_of) do
        lambda do |attributes:|
          if attributes["email"] == "dup@example.com"
            [{origin: :model, code: :value_not_unique, message: "taken", target_column: "email"}]
          else
            []
          end
        end
      end

      it "reports that row as failed with the model's code" do
        expect(chunk_result.failed_rows.map { |failed_row| failed_row.errors.first[:code] }).to eq([:value_not_unique])
      end
    end

    context "with a column that has a default" do
      let(:target_columns) do
        [
          build_target_column(name: "email", required: true),
          build_target_column(name: "status", default: "open"),
          build_target_column(name: "note")
        ]
      end
      let(:mapped_columns) do
        {"email" => {source_column: "Mail"}, "status" => {source_column: "State"}, "note" => {source_column: "Note"}}
      end
      let(:rows) do
        [
          {"Mail" => "a@example.com", "State" => nil, "Note" => nil},
          {"Mail" => "b@example.com", "State" => "closed", "Note" => nil}
        ]
      end

      it "leaves an empty value out of the attributes, so the default fills it" do
        chunk_result

        expect(model_adapter.built_attributes.first).to eq("email" => "a@example.com", "note" => nil)
      end

      it "keeps an empty value that has no default, as an explicit empty value" do
        chunk_result

        expect(model_adapter.built_attributes.first).to include("note" => nil)
      end

      it "keeps a value that is given" do
        chunk_result

        expect(model_adapter.built_attributes.last).to include("status" => "closed")
      end

      it "keeps the empty value in the values of a failed row" do
        failing = FakeModelAdapter.new(errors_of: ->(attributes:) { [{origin: :model, code: :value_invalid, message: "x", target_column: "email"}] })
        result = described_class.call(
          rows: rows, first_row_number: 5, transformer: transformer, schema_checker: schema_checker,
          target_schema: target_schema, model_adapter: failing
        )

        expect(result.failed_rows.first.mapped_values).to include("status" => nil)
      end
    end

    context "when a column that has a default is not mapped" do
      let(:target_columns) do
        [build_target_column(name: "email", required: true), build_target_column(name: "status", default: "open")]
      end
      let(:mapped_columns) { {"email" => {source_column: "Mail"}} }
      let(:rows) { [{"Mail" => "a@example.com"}] }

      it "adds nothing for it" do
        chunk_result

        expect(model_adapter.built_attributes).to eq([{"email" => "a@example.com"}])
      end
    end

    context "when every row is valid" do
      let(:rows) { [{"Mail" => "a@example.com", "State" => "ok"}] }

      it "has no failed rows" do
        expect(chunk_result).to have_attributes(failed_rows: [], valid_rows_count: 1, failed_rows_count: 0)
      end
    end

    describe "the order of the checks and the writes" do
      let(:rows) do
        [
          {"Mail" => "a@example.com", "State" => "ok"},
          {"Mail" => "b@example.com", "State" => "ok"},
          {"Mail" => "c@example.com", "State" => "ok"}
        ]
      end

      it "writes each row right after it is validated, before the next row is validated" do
        chunk_result

        expect(model_adapter.events.map(&:first)).to eq(%i[valid load valid load valid load])
      end

      it "writes the rows in file order" do
        chunk_result

        written_emails = model_adapter.events.select { |event| event.first == :load }.map { |event| event.last["email"] }
        expect(written_emails).to eq(%w[a@example.com b@example.com c@example.com])
      end

      context "when a row is not valid" do
        let(:rows) do
          [
            {"Mail" => "a@example.com", "State" => "ok"},
            {"Mail" => nil, "State" => "ok"},
            {"Mail" => "c@example.com", "State" => "ok"}
          ]
        end

        it "does not write that row, and goes on with the next" do
          chunk_result

          expect(model_adapter.events.map(&:first)).to eq(%i[valid load valid valid load])
        end
      end
    end

    context "when the database refuses a row that passed the validation" do
      let(:rows) do
        [{"Mail" => "a@example.com", "State" => "ok"}, {"Mail" => "dup@example.com", "State" => "ok"}, {"Mail" => "c@example.com", "State" => "ok"}]
      end
      let(:database_error) do
        {origin: :database, code: :value_not_unique, message: "UNIQUE constraint failed", target_column: "email"}
      end
      let(:model_adapter) do
        FakeModelAdapter.new(
          load_errors_of: ->(attributes:) { (attributes["email"] == "dup@example.com") ? [database_error] : [] }
        )
      end

      it "reports that row as failed, with the origin database" do
        expect(chunk_result.failed_rows.map { |failed_row| [failed_row.row_number, failed_row.errors] }).to eq(
          [[6, [database_error]]]
        )
      end

      it "counts it as failed and the others as written" do
        expect(chunk_result).to have_attributes(processed_rows_count: 3, valid_rows_count: 2, failed_rows_count: 1)
      end

      it "goes on with the rows after it" do
        chunk_result

        expect(model_adapter.events.count { |event| event.first == :load }).to eq(3)
      end
    end
  end
end
