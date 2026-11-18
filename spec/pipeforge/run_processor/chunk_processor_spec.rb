# frozen_string_literal: true

RSpec.describe Pipeforge::RunProcessor::ChunkProcessor do
  describe ".call" do
    subject(:chunk_result) do
      described_class.call(
        rows: rows, first_row_number: 5, transformer: transformer, schema_checker: schema_checker,
        resolved_mapped_columns: resolved_mapped_columns, target: target
      )
    end

    let(:target_columns) do
      [
        build_target_column(name: "email", required: true),
        build_target_column(name: "status", max_length: 6)
      ]
    end
    let(:mapped_columns) do
      {
        "email" => {source_column_name: "Mail"},
        "status" => {source_column_name: "State", value_mapping: {"ok" => "active"}}
      }
    end
    let(:resolved_mapped_columns) do
      resolve_mapped_columns_of(target_columns: target_columns, mapped_columns: mapped_columns)
    end
    let(:transformer) { Pipeforge::RunProcessor::RowTransformer.new(resolved_mapped_columns: resolved_mapped_columns) }
    let(:schema_checker) { Pipeforge::RunProcessor::SchemaChecker.new(resolved_mapped_columns: resolved_mapped_columns) }
    let(:target) { FakeTarget.new(errors_of: errors_of) }
    let(:errors_of) { ->(attributes:) { [] } }
    let(:rows) do
      [
        {"Mail" => "a@example.com", "State" => "ok"},
        {"Mail" => nil, "State" => "ok"},
        {"Mail" => "c@example.com", "State" => "far too long"}
      ]
    end

    it "returns a ChunkResult" do
      expect(chunk_result).to be_a(Pipeforge::RunProcessor::ChunkResult)
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

    it "gives each failed row the attributes its record held, after the value mapping" do
      expect(chunk_result.failed_rows.first.attributes).to eq("status" => "active")
    end

    it "gives each failed row its errors with the origin" do
      expect(chunk_result.failed_rows.map { |failed_row| failed_row.errors.map { |error| [error[:code], error[:origin]] } }).to eq(
        [[[:value_missing, :schema]], [[:value_too_long, :schema]]]
      )
    end

    it "builds the record of each row from its transformed values" do
      chunk_result

      expect(target.built_attributes.first).to eq("email" => "a@example.com", "status" => "active")
    end

    it "preloads the parents once, for every record of the chunk" do
      chunk_result

      expect(target.preload_calls.map(&:size)).to eq([3])
    end

    it "preloads after every record is built" do
      allow(target).to receive(:preload_parents).and_wrap_original do |original, **arguments|
        expect(target.built_attributes.size).to eq(3)
        original.call(**arguments)
      end

      chunk_result
    end

    context "when the model finds a mistake in a row" do
      let(:rows) { [{"Mail" => "a@example.com", "State" => "ok"}, {"Mail" => "dup@example.com", "State" => "ok"}] }
      let(:errors_of) do
        lambda do |attributes:|
          if attributes["email"] == "dup@example.com"
            [{origin: :model, code: :value_not_unique, message: "taken", target_column_name: "email"}]
          else
            []
          end
        end
      end

      it "reports that row as failed with the model's code" do
        expect(chunk_result.failed_rows.map { |failed_row| failed_row.errors.first[:code] }).to eq([:value_not_unique])
      end
    end

    describe "the two levels of checks" do
      let(:target_columns) do
        [build_target_column(name: "email", required: true), build_target_column(name: "phone", required: true)]
      end
      let(:mapped_columns) { {"email" => {source_column_name: "Mail"}, "phone" => {source_column_name: "Phone"}} }
      let(:rows) { [{"Mail" => nil, "Phone" => nil}] }
      let(:errors_of_failed_row) { chunk_result.failed_rows.first.errors }

      def model_error(code:, target_column_name:, message: "from the model")
        {origin: :model, code: code, message: message, target_column_name: target_column_name}
      end

      context "when the model finds the same mistake as the schema on one column" do
        let(:errors_of) do
          ->(attributes:) { [model_error(code: :value_missing, target_column_name: "email", message: "model's words")] }
        end

        it "keeps that mistake once, the model's, and the schema's mistake of the other column" do
          expect(errors_of_failed_row.map { |error| [error[:target_column_name], error[:origin]] }).to eq(
            [["email", :model], ["phone", :schema]]
          )
        end

        it "keeps the words of the model" do
          expect(errors_of_failed_row.first[:message]).to eq("model's words")
        end
      end

      context "when the model finds a mistake the schema does not" do
        let(:errors_of) { ->(attributes:) { [model_error(code: :value_invalid, target_column_name: "email")] } }

        it "keeps the model's mistake first, then the schema's" do
          expect(errors_of_failed_row.map { |error| [error[:code], error[:target_column_name]] }).to eq(
            [[:value_invalid, "email"], [:value_missing, "email"], [:value_missing, "phone"]]
          )
        end
      end

      context "when the model's callbacks change a value during its validation" do
        let(:target_columns) { [build_target_column(name: "code", max_length: 3)] }
        let(:mapped_columns) { {"code" => {source_column_name: "Code"}} }
        let(:rows) { [{"Code" => "abc"}, {"Code" => "xyz"}] }

        context "when the change makes a value fit" do
          let(:rows) { [{"Code" => "abcd"}] }
          let(:target) { FakeTarget.new(changes_on_validation: ->(attributes:) { {"code" => "abc"} }) }

          it "does not report the value that was there before" do
            expect(chunk_result.failed_rows).to eq([])
          end
        end

        context "when the change makes a value too long" do
          let(:target) { FakeTarget.new(changes_on_validation: ->(attributes:) { {"code" => "abcd"} }) }

          it "reports the value the model changed it to, and shows it in the failed row" do
            expect(chunk_result.failed_rows.first).to have_attributes(
              attributes: {"code" => "abcd"}, errors: [a_hash_including(code: :value_too_long, origin: :schema)]
            )
          end
        end
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
        {"email" => {source_column_name: "Mail"}, "status" => {source_column_name: "State"}, "note" => {source_column_name: "Note"}}
      end
      let(:rows) do
        [
          {"Mail" => "a@example.com", "State" => nil, "Note" => nil},
          {"Mail" => "b@example.com", "State" => "closed", "Note" => nil}
        ]
      end

      it "leaves an empty value out of the attributes, so the default fills it" do
        chunk_result

        expect(target.built_attributes.first).to eq("email" => "a@example.com")
      end

      it "leaves out an empty value of a column that has no default as well, which is empty without it" do
        chunk_result

        expect(target.built_attributes.first).not_to have_key("note")
      end

      it "keeps a value that is given" do
        chunk_result

        expect(target.built_attributes.last).to include("status" => "closed")
      end

      it "gives the failed row what the record holds, without the empty value of a column that has a default" do
        failing = FakeTarget.new(errors_of: ->(attributes:) { [{origin: :model, code: :value_invalid, message: "x", target_column_name: "email"}] })
        result = described_class.call(
          rows: rows, first_row_number: 5, transformer: transformer, schema_checker: schema_checker,
          resolved_mapped_columns: resolved_mapped_columns, target: failing
        )

        expect(result.failed_rows.first.attributes).to eq("email" => "a@example.com")
      end
    end

    context "when a column that has a default is not mapped" do
      let(:target_columns) do
        [build_target_column(name: "email", required: true), build_target_column(name: "status", default: "open")]
      end
      let(:mapped_columns) { {"email" => {source_column_name: "Mail"}} }
      let(:rows) { [{"Mail" => "a@example.com"}] }

      it "adds nothing for it" do
        chunk_result

        expect(target.built_attributes).to eq([{"email" => "a@example.com"}])
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

        expect(target.events.map(&:first)).to eq(%i[valid load valid load valid load])
      end

      it "writes the rows in file order" do
        chunk_result

        written_emails = target.events.select { |event| event.first == :load }.map { |event| event.last["email"] }
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

          expect(target.events.map(&:first)).to eq(%i[valid load valid valid load])
        end
      end
    end

    context "when the database refuses a row that passed the validation" do
      let(:rows) do
        [{"Mail" => "a@example.com", "State" => "ok"}, {"Mail" => "dup@example.com", "State" => "ok"}, {"Mail" => "c@example.com", "State" => "ok"}]
      end
      let(:database_error) do
        {origin: :database, code: :value_not_unique, message: "UNIQUE constraint failed", target_column_name: "email"}
      end
      let(:target) do
        FakeTarget.new(
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

        expect(target.events.count { |event| event.first == :load }).to eq(3)
      end
    end
  end
end
