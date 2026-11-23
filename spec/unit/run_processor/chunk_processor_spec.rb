# frozen_string_literal: true

# The rows of the source have a source column name ("Mail") that differs from the target column name ("email"), so a
# raw row given to the target instead of the transformer's values shows.
RSpec.describe Pipeforge::RunProcessor::ChunkProcessor do
  let(:scripted_transformer) { instance_double(Pipeforge::RunProcessor::RowTransformer) }
  let(:scripted_schema_checker) { instance_double(Pipeforge::RunProcessor::SchemaChecker) }
  let(:scripted_target) { instance_double(Pipeforge::ActiveRecordTarget, preload_parents: nil) }

  def process_chunk(
    rows:, first_row_number: 1, transformer: scripted_transformer, schema_checker: scripted_schema_checker,
    target: scripted_target
  )
    described_class.call(
      rows: rows, first_row_number: first_row_number, transformer: transformer, schema_checker: schema_checker,
      target: target
    )
  end

  # A verifying double of the model record the target builds. It starts with the given errors (the ones the model's
  # checks found); add_error puts an error into the Hash that errors answers; load answers true, or, when load_error is
  # given, replaces the errors with that one and answers false, as a record does when the database refuses the row.
  def build_model_record(held_attributes:, json_attributes: held_attributes, errors: {}, load_error: nil)
    errors_by_column_name = errors.dup
    model_record = instance_double(Pipeforge::ActiveRecordModelRecord, valid?: true)

    allow(model_record).to receive(:errors).and_return(errors_by_column_name)
    allow(model_record).to receive(:attributes).and_return(held_attributes)
    allow(model_record).to receive(:json_attributes).and_return(json_attributes)
    allow(model_record).to receive(:add_error) do |error:|
      errors_by_column_name[error.target_column_name] = error
    end
    allow(model_record).to receive(:load) do
      if load_error.nil?
        true
      else
        errors_by_column_name.clear
        errors_by_column_name[load_error.target_column_name] = load_error
        false
      end
    end

    model_record
  end

  def script_row(row:, attributes:, model_record:, schema_errors: [])
    allow(scripted_transformer).to receive(:result_of_row).with(row: row).and_return(attributes)
    allow(scripted_target).to receive(:build_record).with(attributes: attributes).and_return(model_record)
    allow(scripted_schema_checker).to receive(:call).with(attributes: model_record.attributes).and_return(schema_errors)
  end

  def model_error_on(target_column_name:, value:)
    Pipeforge::ErrorCatalog::ERRORS.fetch(:value_invalid).call(
      origin: :model, target_column_name: target_column_name, value: value, native_message: "is invalid", error_type: :invalid
    )
  end

  def schema_value_missing_on(target_column_name:)
    Pipeforge::ErrorCatalog::ERRORS.fetch(:value_missing).call(
      origin: :schema, target_column_name: target_column_name, value: nil
    )
  end

  def database_error_not_unique
    Pipeforge::ErrorCatalog::ERRORS.fetch(:value_not_unique).call(
      origin: :database, target_column_name: nil, value: nil, native_message: "duplicate key"
    )
  end

  describe ".call" do
    describe "the promised contract" do
      context "when rows has two rows, the first valid and the second with a schema error, and first_row_number is 4" do
        subject(:chunk_result) { process_chunk(rows: rows_with_a_row_that_fails, first_row_number: 4) }

        let(:rows_with_a_row_that_fails) { [{"Mail" => "a"}, {"Mail" => "b"}] }
        let(:schema_error_on_email) { schema_value_missing_on(target_column_name: "email") }
        let(:failed_row_for_the_second_row) do
          Pipeforge::RunProcessor::FailedRow.new(row_number: 5, attributes: {"email" => "b"}, errors: [schema_error_on_email])
        end
        let(:chunk_result_with_a_failed_row) do
          Pipeforge::RunProcessor::ChunkResult.new(
            first_row_number: 4, last_row_number: 5, processed_rows_count: 2, valid_rows_count: 1, failed_rows_count: 1,
            failed_rows: [failed_row_for_the_second_row]
          )
        end

        before do
          script_row(row: {"Mail" => "a"}, attributes: {"email" => "a"}, model_record: build_model_record(held_attributes: {"email" => "a"}))
          script_row(
            row: {"Mail" => "b"}, attributes: {"email" => "b"}, model_record: build_model_record(held_attributes: {"email" => "b"}),
            schema_errors: [schema_error_on_email]
          )
        end

        # contract only
        it "gives a ChunkResult with first_row_number, last_row_number, processed_rows_count, valid_rows_count, failed_rows_count and failed_rows" do
          expect(chunk_result).to eq(chunk_result_with_a_failed_row)
        end
      end
    end

    describe "the row numbers and the counts" do
      context "when rows has 3 rows that are all valid and first_row_number is 5" do
        subject(:chunk_result) { process_chunk(rows: rows_of_three_valid_rows, first_row_number: 5) }

        let(:rows_of_three_valid_rows) { [{"Mail" => "a"}, {"Mail" => "b"}, {"Mail" => "c"}] }
        let(:chunk_result_from_5_to_7) do
          Pipeforge::RunProcessor::ChunkResult.new(
            first_row_number: 5, last_row_number: 7, processed_rows_count: 3, valid_rows_count: 3, failed_rows_count: 0,
            failed_rows: []
          )
        end

        before do
          rows_of_three_valid_rows.each do |row|
            script_row(row: row, attributes: {"email" => row["Mail"]}, model_record: build_model_record(held_attributes: {"email" => row["Mail"]}))
          end
        end

        it "starts at 5 and ends at 7" do
          expect(chunk_result).to eq(chunk_result_from_5_to_7)
        end
      end

      context "when rows has 3 rows, the first valid, the second with a model error and the third with a schema error" do
        subject(:chunk_result) { process_chunk(rows: rows_with_two_rows_that_fail) }

        let(:rows_with_two_rows_that_fail) { [{"Mail" => "a"}, {"Mail" => "b"}, {"Mail" => "c"}] }
        let(:model_error_on_email) { model_error_on(target_column_name: "email", value: "b") }
        let(:schema_error_on_email) { schema_value_missing_on(target_column_name: "email") }
        let(:chunk_result_with_two_failed_rows) do
          Pipeforge::RunProcessor::ChunkResult.new(
            first_row_number: 1, last_row_number: 3, processed_rows_count: 3, valid_rows_count: 1, failed_rows_count: 2,
            failed_rows: [
              Pipeforge::RunProcessor::FailedRow.new(row_number: 2, attributes: {"email" => "b"}, errors: [model_error_on_email]),
              Pipeforge::RunProcessor::FailedRow.new(row_number: 3, attributes: {"email" => "c"}, errors: [schema_error_on_email])
            ]
          )
        end

        before do
          script_row(row: {"Mail" => "a"}, attributes: {"email" => "a"}, model_record: build_model_record(held_attributes: {"email" => "a"}))
          script_row(
            row: {"Mail" => "b"}, attributes: {"email" => "b"},
            model_record: build_model_record(held_attributes: {"email" => "b"}, errors: {"email" => model_error_on_email})
          )
          script_row(
            row: {"Mail" => "c"}, attributes: {"email" => "c"}, model_record: build_model_record(held_attributes: {"email" => "c"}),
            schema_errors: [schema_error_on_email]
          )
        end

        it "counts 3 as processed_rows_count, 1 as valid_rows_count and 2 as failed_rows_count" do
          expect(chunk_result).to eq(chunk_result_with_two_failed_rows)
        end
      end

      context "when rows has 2 rows that are all valid and first_row_number is 1" do
        subject(:chunk_result) { process_chunk(rows: rows_of_two_valid_rows) }

        let(:rows_of_two_valid_rows) { [{"Mail" => "a"}, {"Mail" => "b"}] }
        let(:chunk_result_of_two_valid_rows) do
          Pipeforge::RunProcessor::ChunkResult.new(
            first_row_number: 1, last_row_number: 2, processed_rows_count: 2, valid_rows_count: 2, failed_rows_count: 0,
            failed_rows: []
          )
        end

        before do
          rows_of_two_valid_rows.each do |row|
            script_row(row: row, attributes: {"email" => row["Mail"]}, model_record: build_model_record(held_attributes: {"email" => row["Mail"]}))
          end
        end

        it "gives no failed row and counts both rows as valid" do
          expect(chunk_result).to eq(chunk_result_of_two_valid_rows)
        end
      end

      context "when a row's load answers false" do
        subject(:chunk_result) { process_chunk(rows: rows_with_a_row_the_database_refuses) }

        let(:rows_with_a_row_the_database_refuses) { [{"Mail" => "a"}] }
        let(:chunk_result_with_a_refused_row) do
          Pipeforge::RunProcessor::ChunkResult.new(
            first_row_number: 1, last_row_number: 1, processed_rows_count: 1, valid_rows_count: 0, failed_rows_count: 1,
            failed_rows: [
              Pipeforge::RunProcessor::FailedRow.new(row_number: 1, attributes: {"email" => "a"}, errors: [database_error_not_unique])
            ]
          )
        end

        before do
          script_row(
            row: {"Mail" => "a"}, attributes: {"email" => "a"},
            model_record: build_model_record(held_attributes: {"email" => "a"}, load_error: database_error_not_unique)
          )
        end

        it "counts the row as failed and not as valid" do
          expect(chunk_result).to eq(chunk_result_with_a_refused_row)
        end
      end
    end

    describe "building the records and preloading" do
      context "when rows has 3 rows and the target gives a record for each" do
        subject(:chunk_result) { process_chunk(rows: rows_of_three_rows) }

        let(:rows_of_three_rows) { [{"Mail" => "a"}, {"Mail" => "b"}, {"Mail" => "c"}] }
        let(:model_record_of_a) { build_model_record(held_attributes: {"email" => "a"}) }
        let(:model_record_of_b) { build_model_record(held_attributes: {"email" => "b"}) }
        let(:model_record_of_c) { build_model_record(held_attributes: {"email" => "c"}) }

        before do
          script_row(row: {"Mail" => "a"}, attributes: {"email" => "a"}, model_record: model_record_of_a)
          script_row(row: {"Mail" => "b"}, attributes: {"email" => "b"}, model_record: model_record_of_b)
          script_row(row: {"Mail" => "c"}, attributes: {"email" => "c"}, model_record: model_record_of_c)
          chunk_result
        end

        it "loads each record the target gave, in file order" do
          expect(model_record_of_a).to have_received(:load).ordered
          expect(model_record_of_b).to have_received(:load).ordered
          expect(model_record_of_c).to have_received(:load).ordered
        end

        it "asks the target once to preload the parents, after all 3 records are built" do
          expect(scripted_target).to have_received(:build_record).exactly(3).times.ordered
          expect(scripted_target).to have_received(:preload_parents).once.ordered
        end
      end
    end

    describe "a row that passes" do
      context "when a record has no error and its load answers true" do
        subject(:chunk_result) { process_chunk(rows: rows_with_a_valid_row) }

        let(:rows_with_a_valid_row) { [{"Mail" => "a"}] }
        let(:record_that_loads) { build_model_record(held_attributes: {"email" => "a"}) }
        let(:chunk_result_with_no_failed_row) do
          Pipeforge::RunProcessor::ChunkResult.new(
            first_row_number: 1, last_row_number: 1, processed_rows_count: 1, valid_rows_count: 1, failed_rows_count: 0,
            failed_rows: []
          )
        end

        before do
          script_row(row: {"Mail" => "a"}, attributes: {"email" => "a"}, model_record: record_that_loads)
        end

        it "loads the record and leaves the row out of the failed rows" do
          expect(chunk_result).to eq(chunk_result_with_no_failed_row)
          expect(record_that_loads).to have_received(:load)
        end
      end
    end

    describe "a row that fails" do
      context "when a record has an error after the model's checks" do
        subject(:chunk_result) { process_chunk(rows: rows_with_a_row_with_a_model_error) }

        let(:rows_with_a_row_with_a_model_error) { [{"Mail" => "a"}] }
        let(:model_error_on_email) { model_error_on(target_column_name: "email", value: "a") }
        let(:record_with_a_model_error) do
          build_model_record(held_attributes: {"email" => "a"}, errors: {"email" => model_error_on_email})
        end
        let(:chunk_result_with_the_model_error) do
          Pipeforge::RunProcessor::ChunkResult.new(
            first_row_number: 1, last_row_number: 1, processed_rows_count: 1, valid_rows_count: 0, failed_rows_count: 1,
            failed_rows: [Pipeforge::RunProcessor::FailedRow.new(row_number: 1, attributes: {"email" => "a"}, errors: [model_error_on_email])]
          )
        end

        before do
          script_row(row: {"Mail" => "a"}, attributes: {"email" => "a"}, model_record: record_with_a_model_error)
        end

        it "does not load the record" do
          chunk_result
          expect(record_with_a_model_error).not_to have_received(:load)
        end

        it "gives a failed row with that error" do
          expect(chunk_result).to eq(chunk_result_with_the_model_error)
        end
      end

      context "when a record has no model error and the schema checker answers an error" do
        subject(:chunk_result) { process_chunk(rows: rows_with_a_row_with_a_schema_error) }

        let(:rows_with_a_row_with_a_schema_error) { [{"Mail" => "a"}] }
        let(:schema_error_on_email) { schema_value_missing_on(target_column_name: "email") }
        let(:record_with_no_model_error) { build_model_record(held_attributes: {"email" => "a"}) }
        let(:chunk_result_with_the_schema_error) do
          Pipeforge::RunProcessor::ChunkResult.new(
            first_row_number: 1, last_row_number: 1, processed_rows_count: 1, valid_rows_count: 0, failed_rows_count: 1,
            failed_rows: [Pipeforge::RunProcessor::FailedRow.new(row_number: 1, attributes: {"email" => "a"}, errors: [schema_error_on_email])]
          )
        end

        before do
          script_row(
            row: {"Mail" => "a"}, attributes: {"email" => "a"}, model_record: record_with_no_model_error,
            schema_errors: [schema_error_on_email]
          )
        end

        it "does not load the record" do
          chunk_result
          expect(record_with_no_model_error).not_to have_received(:load)
        end

        it "gives a failed row with the error of the schema" do
          expect(chunk_result).to eq(chunk_result_with_the_schema_error)
        end
      end

      context "when a record's load answers false and the record then holds the error of the database" do
        subject(:chunk_result) { process_chunk(rows: rows_with_a_row_the_database_refuses) }

        let(:rows_with_a_row_the_database_refuses) { [{"Mail" => "a"}] }
        let(:record_refused_by_the_database) do
          build_model_record(held_attributes: {"email" => "a"}, load_error: database_error_not_unique)
        end
        let(:chunk_result_with_the_database_error) do
          Pipeforge::RunProcessor::ChunkResult.new(
            first_row_number: 1, last_row_number: 1, processed_rows_count: 1, valid_rows_count: 0, failed_rows_count: 1,
            failed_rows: [
              Pipeforge::RunProcessor::FailedRow.new(row_number: 1, attributes: {"email" => "a"}, errors: [database_error_not_unique])
            ]
          )
        end

        before do
          script_row(row: {"Mail" => "a"}, attributes: {"email" => "a"}, model_record: record_refused_by_the_database)
        end

        it "gives a failed row with the errors the record holds then" do
          expect(chunk_result).to eq(chunk_result_with_the_database_error)
        end
      end

      context "when a record has a model error on email and the schema checker answers an error on name" do
        subject(:chunk_result) { process_chunk(rows: rows_with_a_row_with_two_errors) }

        let(:rows_with_a_row_with_two_errors) { [{"Mail" => "a"}] }
        let(:model_error_on_email) { model_error_on(target_column_name: "email", value: "a") }
        let(:schema_error_on_name) { schema_value_missing_on(target_column_name: "name") }
        let(:record_with_a_model_error_on_email) do
          build_model_record(held_attributes: {"email" => "a", "name" => nil}, errors: {"email" => model_error_on_email})
        end
        let(:chunk_result_with_both_errors) do
          Pipeforge::RunProcessor::ChunkResult.new(
            first_row_number: 1, last_row_number: 1, processed_rows_count: 1, valid_rows_count: 0, failed_rows_count: 1,
            failed_rows: [
              Pipeforge::RunProcessor::FailedRow.new(
                row_number: 1, attributes: {"email" => "a", "name" => nil}, errors: [model_error_on_email, schema_error_on_name]
              )
            ]
          )
        end

        before do
          script_row(
            row: {"Mail" => "a"}, attributes: {"email" => "a"}, model_record: record_with_a_model_error_on_email,
            schema_errors: [schema_error_on_name]
          )
        end

        it "gives a failed row with both errors" do
          expect(chunk_result).to eq(chunk_result_with_both_errors)
        end
      end
    end

    describe "the errors of the two levels" do
      context "when the schema checker answers an error on email and an error on name for a record" do
        subject(:chunk_result) { process_chunk(rows: rows_of_one_row) }

        let(:rows_of_one_row) { [{"Mail" => "a"}] }
        let(:record_with_schema_errors) { build_model_record(held_attributes: {"email" => "a", "name" => "n"}) }
        let(:schema_error_on_email) { schema_value_missing_on(target_column_name: "email") }
        let(:schema_error_on_name) { schema_value_missing_on(target_column_name: "name") }
        let(:chunk_result_with_both_schema_errors) do
          Pipeforge::RunProcessor::ChunkResult.new(
            first_row_number: 1, last_row_number: 1, processed_rows_count: 1, valid_rows_count: 0, failed_rows_count: 1,
            failed_rows: [
              Pipeforge::RunProcessor::FailedRow.new(
                row_number: 1, attributes: {"email" => "a", "name" => "n"}, errors: [schema_error_on_email, schema_error_on_name]
              )
            ]
          )
        end

        before do
          script_row(
            row: {"Mail" => "a"}, attributes: {"email" => "a"}, model_record: record_with_schema_errors,
            schema_errors: [schema_error_on_email, schema_error_on_name]
          )
        end

        it "gives a failed row with both errors, in the order the schema checker answered them" do
          expect(chunk_result).to eq(chunk_result_with_both_schema_errors)
        end
      end

      context "when the schema checker answers no error for a record" do
        subject(:chunk_result) { process_chunk(rows: rows_of_one_row) }

        let(:rows_of_one_row) { [{"Mail" => "a"}] }
        let(:record_with_no_schema_error) { build_model_record(held_attributes: {"email" => "a"}) }

        before do
          script_row(row: {"Mail" => "a"}, attributes: {"email" => "a"}, model_record: record_with_no_schema_error)
          chunk_result
        end

        it "does not call add_error" do
          expect(record_with_no_schema_error).not_to have_received(:add_error)
        end
      end
    end

    describe "what a failed row shows" do
      context "when the second row of rows fails and first_row_number is 5" do
        subject(:chunk_result) { process_chunk(rows: rows_with_the_second_row_failing, first_row_number: 5) }

        let(:rows_with_the_second_row_failing) { [{"Mail" => "a"}, {"Mail" => "b"}] }
        let(:model_error_on_email) { model_error_on(target_column_name: "email", value: "b") }
        let(:chunk_result_with_the_second_row_failed) do
          Pipeforge::RunProcessor::ChunkResult.new(
            first_row_number: 5, last_row_number: 6, processed_rows_count: 2, valid_rows_count: 1, failed_rows_count: 1,
            failed_rows: [Pipeforge::RunProcessor::FailedRow.new(row_number: 6, attributes: {"email" => "b"}, errors: [model_error_on_email])]
          )
        end

        before do
          script_row(row: {"Mail" => "a"}, attributes: {"email" => "a"}, model_record: build_model_record(held_attributes: {"email" => "a"}))
          script_row(
            row: {"Mail" => "b"}, attributes: {"email" => "b"},
            model_record: build_model_record(held_attributes: {"email" => "b"}, errors: {"email" => model_error_on_email})
          )
        end

        it "gives the failed row the row number 6" do
          expect(chunk_result).to eq(chunk_result_with_the_second_row_failed)
        end
      end

      context "when json_attributes of the record has several columns, one of them not filled by the row" do
        subject(:chunk_result) { process_chunk(rows: rows_with_a_failing_row) }

        let(:rows_with_a_failing_row) { [{"Mail" => "a"}] }
        let(:model_error_on_email) { model_error_on(target_column_name: "email", value: "a") }
        let(:json_attributes_with_an_unfilled_column) { {"id" => nil, "email" => "a", "age" => nil, "name" => "n"} }
        let(:record_with_several_columns) do
          build_model_record(
            held_attributes: {"email" => "a"}, json_attributes: json_attributes_with_an_unfilled_column,
            errors: {"email" => model_error_on_email}
          )
        end
        let(:chunk_result_with_every_column) do
          Pipeforge::RunProcessor::ChunkResult.new(
            first_row_number: 1, last_row_number: 1, processed_rows_count: 1, valid_rows_count: 0, failed_rows_count: 1,
            failed_rows: [
              Pipeforge::RunProcessor::FailedRow.new(
                row_number: 1, attributes: json_attributes_with_an_unfilled_column, errors: [model_error_on_email]
              )
            ]
          )
        end

        before do
          script_row(row: {"Mail" => "a"}, attributes: {"email" => "a"}, model_record: record_with_several_columns)
        end

        it "shows every column of json_attributes, with its value" do
          expect(chunk_result).to eq(chunk_result_with_every_column)
        end

        it "shows the columns in the order of json_attributes" do
          expect(chunk_result.failed_rows.first.attributes.to_a).to eq(json_attributes_with_an_unfilled_column.to_a)
        end
      end

      context "when errors of the record has the columns email and name" do
        subject(:chunk_result) { process_chunk(rows: rows_with_a_failing_row) }

        let(:rows_with_a_failing_row) { [{"Mail" => "a"}] }
        let(:model_error_on_name) { model_error_on(target_column_name: "name", value: "n") }
        let(:model_error_on_email) { model_error_on(target_column_name: "email", value: "a") }
        let(:record_with_errors_on_name_and_email) do
          build_model_record(
            held_attributes: {"email" => "a", "name" => "n"},
            errors: {"name" => model_error_on_name, "email" => model_error_on_email}
          )
        end
        let(:chunk_result_with_errors_in_the_order_of_errors) do
          Pipeforge::RunProcessor::ChunkResult.new(
            first_row_number: 1, last_row_number: 1, processed_rows_count: 1, valid_rows_count: 0, failed_rows_count: 1,
            failed_rows: [
              Pipeforge::RunProcessor::FailedRow.new(
                row_number: 1, attributes: {"email" => "a", "name" => "n"}, errors: [model_error_on_name, model_error_on_email]
              )
            ]
          )
        end

        before do
          script_row(row: {"Mail" => "a"}, attributes: {"email" => "a"}, model_record: record_with_errors_on_name_and_email)
        end

        it "holds the error objects in the order of errors.values" do
          expect(chunk_result).to eq(chunk_result_with_errors_in_the_order_of_errors)
        end
      end

      context "when two rows of rows fail" do
        subject(:chunk_result) { process_chunk(rows: rows_with_two_failing_rows, first_row_number: 10) }

        let(:rows_with_two_failing_rows) { [{"Mail" => "a"}, {"Mail" => "b"}] }
        let(:model_error_on_a) { model_error_on(target_column_name: "email", value: "a") }
        let(:model_error_on_b) { model_error_on(target_column_name: "email", value: "b") }
        let(:chunk_result_with_failed_rows_in_file_order) do
          Pipeforge::RunProcessor::ChunkResult.new(
            first_row_number: 10, last_row_number: 11, processed_rows_count: 2, valid_rows_count: 0, failed_rows_count: 2,
            failed_rows: [
              Pipeforge::RunProcessor::FailedRow.new(row_number: 10, attributes: {"email" => "a"}, errors: [model_error_on_a]),
              Pipeforge::RunProcessor::FailedRow.new(row_number: 11, attributes: {"email" => "b"}, errors: [model_error_on_b])
            ]
          )
        end

        before do
          script_row(
            row: {"Mail" => "a"}, attributes: {"email" => "a"},
            model_record: build_model_record(held_attributes: {"email" => "a"}, errors: {"email" => model_error_on_a})
          )
          script_row(
            row: {"Mail" => "b"}, attributes: {"email" => "b"},
            model_record: build_model_record(held_attributes: {"email" => "b"}, errors: {"email" => model_error_on_b})
          )
        end

        it "holds the failed rows in file order" do
          expect(chunk_result).to eq(chunk_result_with_failed_rows_in_file_order)
        end
      end
    end

    context "when rows has two valid rows" do
      subject(:chunk_result) { process_chunk(rows: rows_of_two_valid_rows) }

      let(:rows_of_two_valid_rows) { [{"Mail" => "a"}, {"Mail" => "b"}] }
      let(:first_record_that_loads) { build_model_record(held_attributes: {"email" => "a"}) }
      let(:second_record_that_loads) { build_model_record(held_attributes: {"email" => "b"}) }

      before do
        script_row(row: {"Mail" => "a"}, attributes: {"email" => "a"}, model_record: first_record_that_loads)
        script_row(row: {"Mail" => "b"}, attributes: {"email" => "b"}, model_record: second_record_that_loads)
        chunk_result
      end

      it "loads the first record before it validates the second" do
        expect(first_record_that_loads).to have_received(:load).ordered
        expect(second_record_that_loads).to have_received(:valid?).ordered
      end
    end

    context "when rows has two rows whose records have an error" do
      subject(:chunk_result) { process_chunk(rows: rows_with_two_rows_that_fail) }

      let(:rows_with_two_rows_that_fail) { [{"Mail" => "a"}, {"Mail" => "b"}] }
      let(:record_with_a_model_error) do
        build_model_record(held_attributes: {"email" => "a"}, errors: {"email" => model_error_on(target_column_name: "email", value: "a")})
      end
      let(:record_with_a_schema_error) { build_model_record(held_attributes: {"email" => "b"}) }

      before do
        script_row(row: {"Mail" => "a"}, attributes: {"email" => "a"}, model_record: record_with_a_model_error)
        script_row(
          row: {"Mail" => "b"}, attributes: {"email" => "b"}, model_record: record_with_a_schema_error,
          schema_errors: [schema_value_missing_on(target_column_name: "email")]
        )
        chunk_result
      end

      it "never loads a record that has an error" do
        expect(record_with_a_model_error).not_to have_received(:load)
        expect(record_with_a_schema_error).not_to have_received(:load)
      end
    end

    context "when rows has a valid row, a row with a model error, a row with a schema error and a row the database refuses" do
      subject(:chunk_result) { process_chunk(rows: rows_of_four_kinds) }

      let(:rows_of_four_kinds) { [{"Mail" => "a"}, {"Mail" => "b"}, {"Mail" => "c"}, {"Mail" => "d"}] }

      before do
        script_row(row: {"Mail" => "a"}, attributes: {"email" => "a"}, model_record: build_model_record(held_attributes: {"email" => "a"}))
        script_row(
          row: {"Mail" => "b"}, attributes: {"email" => "b"},
          model_record: build_model_record(held_attributes: {"email" => "b"}, errors: {"email" => model_error_on(target_column_name: "email", value: "b")})
        )
        script_row(
          row: {"Mail" => "c"}, attributes: {"email" => "c"}, model_record: build_model_record(held_attributes: {"email" => "c"}),
          schema_errors: [schema_value_missing_on(target_column_name: "email")]
        )
        script_row(
          row: {"Mail" => "d"}, attributes: {"email" => "d"},
          model_record: build_model_record(held_attributes: {"email" => "d"}, load_error: database_error_not_unique)
        )
      end

      it "counts processed_rows_count as valid_rows_count plus failed_rows_count" do
        expect(chunk_result.valid_rows_count + chunk_result.failed_rows_count).to eq(chunk_result.processed_rows_count)
      end
    end

    context "when rows has one row" do
      subject(:chunk_result) { process_chunk(rows: rows_of_one_row) }

      let(:rows_of_one_row) { [{"Mail" => "a"}] }
      let(:record_that_is_validated) { build_model_record(held_attributes: {"email" => "a"}) }

      before do
        script_row(row: {"Mail" => "a"}, attributes: {"email" => "a"}, model_record: record_that_is_validated)
        chunk_result
      end

      it "asks the schema checker after valid? ran" do
        expect(record_that_is_validated).to have_received(:valid?).ordered
        expect(scripted_schema_checker).to have_received(:call).ordered
      end
    end

    context "when the schema checker answers an error for a record" do
      subject(:chunk_result) { process_chunk(rows: rows_of_one_row) }

      let(:rows_of_one_row) { [{"Mail" => "a"}] }
      let(:record_with_a_schema_error) { build_model_record(held_attributes: {"email" => "a"}) }

      before do
        script_row(
          row: {"Mail" => "a"}, attributes: {"email" => "a"}, model_record: record_with_a_schema_error,
          schema_errors: [schema_value_missing_on(target_column_name: "email")]
        )
        chunk_result
      end

      it "runs valid? before it adds the schema's errors" do
        expect(record_with_a_schema_error).to have_received(:valid?).ordered
        expect(record_with_a_schema_error).to have_received(:add_error).ordered
      end
    end

    describe "collaboration" do
      describe "with the real RowTransformer" do
        context "when the mapping reads the source column Mail into email and the row has that cell" do
          subject(:chunk_result) do
            process_chunk(rows: rows_with_a_mail_cell, transformer: real_transformer_of_mail_into_email)
          end

          let(:rows_with_a_mail_cell) { [{"Mail" => "ann@example.com"}] }
          let(:real_transformer_of_mail_into_email) do
            Pipeforge::RunProcessor::RowTransformer.new(
              resolved_mapped_columns: resolve_mapped_columns("email" => {source_column_name: "Mail"})
            )
          end
          let(:record_built_from_the_mail_cell) { build_model_record(held_attributes: {"email" => "ann@example.com"}) }

          before do
            allow(real_transformer_of_mail_into_email).to receive(:result_of_row).and_call_original
            allow(scripted_target).to receive(:build_record).and_return(record_built_from_the_mail_cell)
            allow(scripted_schema_checker).to receive(:call).and_return([])
            chunk_result
          end

          it "asks the transformer for the values of the row" do
            expect(real_transformer_of_mail_into_email).to have_received(:result_of_row).with(row: {"Mail" => "ann@example.com"})
          end

          it "asks the target to build the record with the cell under email" do
            expect(scripted_target).to have_received(:build_record).with(attributes: {"email" => "ann@example.com"})
          end

          it "loads the record the target gave" do
            expect(record_built_from_the_mail_cell).to have_received(:load)
          end
        end
      end

      describe "with the real SchemaChecker" do
        # The transformer gives no values and the target builds the given record, so what the schema checker is asked
        # about is only what the record holds.
        def script_one_record(row:, model_record:)
          allow(scripted_transformer).to receive(:result_of_row).with(row: row).and_return({})
          allow(scripted_target).to receive(:build_record).with(attributes: {}).and_return(model_record)
        end

        context "when email is required and the record holds nil for it" do
          subject(:chunk_result) do
            process_chunk(rows: rows_with_an_empty_cell, schema_checker: real_schema_checker_of_required_email)
          end

          let(:rows_with_an_empty_cell) { [{"Mail" => nil}] }
          let(:required_email_column) { build_target_column(name: "email", required: true) }
          let(:real_schema_checker_of_required_email) do
            Pipeforge::RunProcessor::SchemaChecker.new(
              resolved_mapped_columns: resolve_mapped_columns_of(
                target_columns: [required_email_column], mapped_columns: {"email" => {source_column_name: "Mail"}}
              )
            )
          end
          let(:record_with_nil_email) do
            build_model_record(held_attributes: {"email" => nil}, json_attributes: {"id" => nil, "email" => nil})
          end
          let(:schema_error_on_email) { schema_value_missing_on(target_column_name: "email") }
          let(:chunk_result_with_value_missing) do
            Pipeforge::RunProcessor::ChunkResult.new(
              first_row_number: 1, last_row_number: 1, processed_rows_count: 1, valid_rows_count: 0, failed_rows_count: 1,
              failed_rows: [
                Pipeforge::RunProcessor::FailedRow.new(
                  row_number: 1, attributes: {"id" => nil, "email" => nil}, errors: [schema_error_on_email]
                )
              ]
            )
          end

          before do
            script_one_record(row: {"Mail" => nil}, model_record: record_with_nil_email)
            allow(real_schema_checker_of_required_email).to receive(:call).and_call_original
            chunk_result
          end

          it "asks the schema checker with what attributes of the record answers" do
            expect(real_schema_checker_of_required_email).to have_received(:call).with(attributes: record_with_nil_email.attributes)
          end

          it "adds the value_missing error of the schema checker to the record with add_error" do
            expect(record_with_nil_email).to have_received(:add_error).with(error: schema_error_on_email)
          end

          it "gives a failed row with value_missing from the schema" do
            expect(chunk_result).to eq(chunk_result_with_value_missing)
          end

          it "does not load the record" do
            expect(record_with_nil_email).not_to have_received(:load)
          end
        end

        context "when email and name are required and the record holds nil for both" do
          subject(:chunk_result) do
            process_chunk(rows: rows_with_two_empty_cells, schema_checker: real_schema_checker_of_required_email_and_name)
          end

          let(:rows_with_two_empty_cells) { [{"Mail" => nil, "Name" => nil}] }
          let(:real_schema_checker_of_required_email_and_name) do
            Pipeforge::RunProcessor::SchemaChecker.new(
              resolved_mapped_columns: resolve_mapped_columns_of(
                target_columns: [build_target_column(name: "email", required: true), build_target_column(name: "name", required: true)],
                mapped_columns: {"email" => {source_column_name: "Mail"}, "name" => {source_column_name: "Name"}}
              )
            )
          end
          let(:record_with_nil_email_and_name) { build_model_record(held_attributes: {"email" => nil, "name" => nil}) }
          let(:schema_error_on_email) { schema_value_missing_on(target_column_name: "email") }
          let(:schema_error_on_name) { schema_value_missing_on(target_column_name: "name") }
          let(:chunk_result_with_two_value_missing) do
            Pipeforge::RunProcessor::ChunkResult.new(
              first_row_number: 1, last_row_number: 1, processed_rows_count: 1, valid_rows_count: 0, failed_rows_count: 1,
              failed_rows: [
                Pipeforge::RunProcessor::FailedRow.new(
                  row_number: 1, attributes: {"email" => nil, "name" => nil}, errors: [schema_error_on_email, schema_error_on_name]
                )
              ]
            )
          end

          before do
            script_one_record(row: {"Mail" => nil, "Name" => nil}, model_record: record_with_nil_email_and_name)
            chunk_result
          end

          it "adds each error of the schema checker to the record with add_error, in the order of the mapped columns" do
            expect(record_with_nil_email_and_name).to have_received(:add_error).with(error: schema_error_on_email).ordered
            expect(record_with_nil_email_and_name).to have_received(:add_error).with(error: schema_error_on_name).ordered
          end

          it "gives a failed row with both errors" do
            expect(chunk_result).to eq(chunk_result_with_two_value_missing)
          end
        end

        context "when email is required and the record holds a value for it" do
          subject(:chunk_result) do
            process_chunk(rows: rows_with_an_email_cell, schema_checker: real_schema_checker_of_required_email)
          end

          let(:rows_with_an_email_cell) { [{"Mail" => "a"}] }
          let(:real_schema_checker_of_required_email) do
            Pipeforge::RunProcessor::SchemaChecker.new(
              resolved_mapped_columns: resolve_mapped_columns_of(
                target_columns: [build_target_column(name: "email", required: true)],
                mapped_columns: {"email" => {source_column_name: "Mail"}}
              )
            )
          end
          let(:record_with_an_email) { build_model_record(held_attributes: {"email" => "a"}) }
          let(:chunk_result_with_no_failed_row) do
            Pipeforge::RunProcessor::ChunkResult.new(
              first_row_number: 1, last_row_number: 1, processed_rows_count: 1, valid_rows_count: 1, failed_rows_count: 0,
              failed_rows: []
            )
          end

          before { script_one_record(row: {"Mail" => "a"}, model_record: record_with_an_email) }

          it "does not call add_error on the record" do
            chunk_result
            expect(record_with_an_email).not_to have_received(:add_error)
          end

          it "gives no failed row" do
            expect(chunk_result).to eq(chunk_result_with_no_failed_row)
          end
        end
      end

      describe "with the real ActiveRecordTarget and its ActiveRecordModelRecord" do
        def script_email_rows(rows:, schema_errors: [])
          rows.each do |row|
            allow(scripted_transformer).to receive(:result_of_row).with(row: row).and_return({"email" => row["Mail"]})
          end
          allow(scripted_schema_checker).to receive(:call).and_return(schema_errors)
        end

        context "when the real target builds a record for each of three rows" do
          subject(:chunk_result) { process_chunk(rows: rows_of_three_emails, target: real_target) }

          let(:rows_of_three_emails) { [{"Mail" => "a"}, {"Mail" => "b"}, {"Mail" => "c"}] }
          let(:model_of_three_rows) do
            define_model(name: "ModelOfThreeRows", columns: ->(table) { table.string :email })
          end
          let(:real_target) { Pipeforge::ActiveRecordTarget.new(target_model_name: model_of_three_rows.name) }
          let(:records_built_by_the_target) { [] }

          before do
            script_email_rows(rows: rows_of_three_emails)
            allow(real_target).to receive(:preload_parents).and_call_original
            allow(real_target).to receive(:build_record).and_wrap_original do |build_record, **keywords|
              build_record.call(**keywords).tap { |model_record| records_built_by_the_target << model_record }
            end
            chunk_result
          end

          it "calls preload_parents once on the target, with the three records, after all three are built" do
            expect(real_target).to have_received(:build_record).exactly(3).times.ordered
            expect(real_target).to have_received(:preload_parents).with(records: records_built_by_the_target).once.ordered
          end
        end

        context "when the model accepts the row and the table takes it" do
          subject(:chunk_result) { process_chunk(rows: rows_with_an_email, target: real_target) }

          let(:rows_with_an_email) { [{"Mail" => "ann@example.com"}] }
          let(:model_that_accepts_any_email) do
            define_model(name: "ModelThatAcceptsAnyEmail", columns: ->(table) { table.string :email })
          end
          let(:real_target) { Pipeforge::ActiveRecordTarget.new(target_model_name: model_that_accepts_any_email.name) }
          let(:chunk_result_with_no_failed_row) do
            Pipeforge::RunProcessor::ChunkResult.new(
              first_row_number: 1, last_row_number: 1, processed_rows_count: 1, valid_rows_count: 1, failed_rows_count: 0,
              failed_rows: []
            )
          end

          before { script_email_rows(rows: rows_with_an_email) }

          # contract only
          it "writes the row and gives no failed row" do
            expect(chunk_result).to eq(chunk_result_with_no_failed_row)
            expect(model_that_accepts_any_email.pluck(:email)).to eq(["ann@example.com"])
          end
        end

        context "when the model refuses the row with a validation" do
          subject(:chunk_result) { process_chunk(rows: rows_with_an_email_without_an_at_sign, target: real_target) }

          let(:rows_with_an_email_without_an_at_sign) { [{"Mail" => "no-at-sign"}] }
          let(:model_that_validates_the_format_of_email) do
            define_model(name: "ModelThatValidatesTheFormatOfEmail", columns: ->(table) { table.string :email }) do
              validates :email, format: {with: /@/}
            end
          end
          let(:real_target) { Pipeforge::ActiveRecordTarget.new(target_model_name: model_that_validates_the_format_of_email.name) }
          let(:chunk_result_with_a_model_error) do
            Pipeforge::RunProcessor::ChunkResult.new(
              first_row_number: 1, last_row_number: 1, processed_rows_count: 1, valid_rows_count: 0, failed_rows_count: 1,
              failed_rows: [
                Pipeforge::RunProcessor::FailedRow.new(
                  row_number: 1, attributes: {"id" => nil, "email" => "no-at-sign"},
                  errors: [model_error_on(target_column_name: "email", value: "no-at-sign")]
                )
              ]
            )
          end

          before { script_email_rows(rows: rows_with_an_email_without_an_at_sign) }

          it "gives a failed row with origin :model" do
            expect(chunk_result).to eq(chunk_result_with_a_model_error)
          end

          it "does not write the row" do
            chunk_result
            expect(model_that_validates_the_format_of_email.count).to eq(0)
          end
        end

        context "when the table refuses the second of three rows with a unique index" do
          subject(:chunk_result) { process_chunk(rows: rows_with_a_repeated_email, target: real_target) }

          let(:rows_with_a_repeated_email) { [{"Mail" => "a"}, {"Mail" => "a"}, {"Mail" => "b"}] }
          let(:model_with_a_unique_index_on_email) do
            define_model(
              name: "ModelWithAUniqueIndexOnEmail",
              columns: ->(table) {
                table.string :email
                table.index :email, unique: true
              }
            )
          end
          let(:real_target) { Pipeforge::ActiveRecordTarget.new(target_model_name: model_with_a_unique_index_on_email.name) }
          let(:chunk_result_with_a_database_error) do
            Pipeforge::RunProcessor::ChunkResult.new(
              first_row_number: 1, last_row_number: 3, processed_rows_count: 3, valid_rows_count: 2, failed_rows_count: 1,
              failed_rows: [
                Pipeforge::RunProcessor::FailedRow.new(
                  row_number: 2, attributes: {"id" => nil, "email" => "a"},
                  errors: [
                    Pipeforge::ErrorCatalog::ERRORS.fetch(:value_not_unique).call(
                      origin: :database, target_column_name: nil, value: nil, native_message: native_message_of_the_unique_index
                    )
                  ]
                )
              ]
            )
          end
          let(:native_message_of_the_unique_index) do
            "PG::UniqueViolation: ERROR:  duplicate key value violates unique constraint " \
              "\"index_model_with_a_unique_index_on_email_on_email\"\nDETAIL:  Key (email)=(a) already exists.\n"
          end

          before { script_email_rows(rows: rows_with_a_repeated_email) }

          it "gives a failed row with origin :database" do
            expect(chunk_result).to eq(chunk_result_with_a_database_error)
          end

          it "still writes the rows after it" do
            chunk_result
            expect(model_with_a_unique_index_on_email.order(:id).pluck(:email)).to eq(%w[a b])
          end
        end

        context "when the model and the schema checker each find an error on email" do
          subject(:chunk_result) { process_chunk(rows: rows_with_an_email_without_an_at_sign, target: real_target) }

          let(:rows_with_an_email_without_an_at_sign) { [{"Mail" => "no-at-sign"}] }
          let(:model_that_validates_the_format_of_email) do
            define_model(name: "ModelThatValidatesTheFormatOfEmailAgain", columns: ->(table) { table.string :email }) do
              validates :email, format: {with: /@/}
            end
          end
          let(:real_target) { Pipeforge::ActiveRecordTarget.new(target_model_name: model_that_validates_the_format_of_email.name) }
          let(:chunk_result_with_the_model_error_only) do
            Pipeforge::RunProcessor::ChunkResult.new(
              first_row_number: 1, last_row_number: 1, processed_rows_count: 1, valid_rows_count: 0, failed_rows_count: 1,
              failed_rows: [
                Pipeforge::RunProcessor::FailedRow.new(
                  row_number: 1, attributes: {"id" => nil, "email" => "no-at-sign"},
                  errors: [model_error_on(target_column_name: "email", value: "no-at-sign")]
                )
              ]
            )
          end

          before do
            script_email_rows(
              rows: rows_with_an_email_without_an_at_sign,
              schema_errors: [schema_value_missing_on(target_column_name: "email")]
            )
          end

          it "gives a failed row with one error for the column, the model's" do
            expect(chunk_result).to eq(chunk_result_with_the_model_error_only)
          end
        end
      end

      describe "with all the real collaborators" do
        context "when rows has a row that passes, one with an empty name, one the model refuses and one the table refuses, and first_row_number is 5" do
          subject(:chunk_result) do
            described_class.call(
              rows: rows_of_four_kinds, first_row_number: 5, transformer: real_transformer, schema_checker: real_schema_checker,
              target: real_target
            )
          end

          let(:rows_of_four_kinds) do
            [
              {"Mail" => "ann@example.com", "Name" => "Ann"},
              {"Mail" => "bob@example.com", "Name" => nil},
              {"Mail" => "no-at-sign", "Name" => "Cy"},
              {"Mail" => "ann@example.com", "Name" => "Dee"}
            ]
          end
          let(:mapped_columns_of_email_and_name) do
            {"email" => {source_column_name: "Mail"}, "name" => {source_column_name: "Name"}}
          end
          let(:required_name_column) { build_target_column(name: "name", required: true) }
          let(:real_transformer) do
            Pipeforge::RunProcessor::RowTransformer.new(
              resolved_mapped_columns: resolve_mapped_columns_of(
                target_columns: [build_target_column(name: "email"), required_name_column],
                mapped_columns: mapped_columns_of_email_and_name
              )
            )
          end
          let(:real_schema_checker) do
            Pipeforge::RunProcessor::SchemaChecker.new(
              resolved_mapped_columns: resolve_mapped_columns_of(
                target_columns: [build_target_column(name: "email"), required_name_column],
                mapped_columns: mapped_columns_of_email_and_name
              )
            )
          end
          let(:model_with_a_format_and_a_unique_index_on_email) do
            define_model(
              name: "ModelWithAFormatAndAUniqueIndexOnEmail",
              columns: ->(table) {
                table.string :email
                table.string :name
                table.index :email, unique: true
              }
            ) do
              validates :email, format: {with: /@/}
            end
          end
          let(:real_target) do
            Pipeforge::ActiveRecordTarget.new(target_model_name: model_with_a_format_and_a_unique_index_on_email.name)
          end
          let(:native_message_of_the_unique_index) do
            "PG::UniqueViolation: ERROR:  duplicate key value violates unique constraint " \
              "\"index_model_with_a_format_and_a_unique_index_on_email_on_email\"\n" \
              "DETAIL:  Key (email)=(ann@example.com) already exists.\n"
          end
          let(:expected_chunk_result) do
            Pipeforge::RunProcessor::ChunkResult.new(
              first_row_number: 5, last_row_number: 8, processed_rows_count: 4, valid_rows_count: 1, failed_rows_count: 3,
              failed_rows: [
                Pipeforge::RunProcessor::FailedRow.new(
                  row_number: 6, attributes: {"id" => nil, "email" => "bob@example.com", "name" => nil},
                  errors: [schema_value_missing_on(target_column_name: "name")]
                ),
                Pipeforge::RunProcessor::FailedRow.new(
                  row_number: 7, attributes: {"id" => nil, "email" => "no-at-sign", "name" => "Cy"},
                  errors: [model_error_on(target_column_name: "email", value: "no-at-sign")]
                ),
                Pipeforge::RunProcessor::FailedRow.new(
                  row_number: 8, attributes: {"id" => nil, "email" => "ann@example.com", "name" => "Dee"},
                  errors: [
                    Pipeforge::ErrorCatalog::ERRORS.fetch(:value_not_unique).call(
                      origin: :database, target_column_name: nil, value: nil, native_message: native_message_of_the_unique_index
                    )
                  ]
                )
              ]
            )
          end

          let(:records_built_by_the_target) { [] }
          let(:attributes_of_the_records_when_built) { [] }
          let(:values_of_the_rows) do
            [
              {"email" => "ann@example.com", "name" => "Ann"},
              {"email" => "bob@example.com"},
              {"email" => "no-at-sign", "name" => "Cy"},
              {"email" => "ann@example.com", "name" => "Dee"}
            ]
          end

          before do
            allow(real_transformer).to receive(:result_of_row).and_call_original
            allow(real_schema_checker).to receive(:call).and_call_original
            allow(real_target).to receive(:preload_parents).and_call_original
            allow(real_target).to receive(:build_record).and_wrap_original do |build_record, **keywords|
              build_record.call(**keywords).tap do |model_record|
                records_built_by_the_target << model_record
                attributes_of_the_records_when_built << model_record.attributes
              end
            end
            chunk_result
          end

          it "asks the transformer for the values of each row" do
            rows_of_four_kinds.each do |row|
              expect(real_transformer).to have_received(:result_of_row).with(row: row)
            end
          end

          it "asks the target to build each record with the values the transformer gave" do
            values_of_the_rows.each do |values|
              expect(real_target).to have_received(:build_record).with(attributes: values)
            end
          end

          it "asks the schema checker with what attributes of each record answered" do
            attributes_of_the_records_when_built.each do |attributes|
              expect(real_schema_checker).to have_received(:call).with(attributes: attributes)
            end
          end

          it "asks the target once to preload the parents, with the four records" do
            expect(real_target).to have_received(:preload_parents).with(records: records_built_by_the_target).once
          end

          it "gives the ChunkResult with the three failed rows and their errors from the three origins" do
            expect(chunk_result).to eq(expected_chunk_result)
          end

          it "writes the row that passes" do
            chunk_result
            expect(model_with_a_format_and_a_unique_index_on_email.pluck(:email, :name)).to eq([["ann@example.com", "Ann"]])
          end
        end
      end
    end
  end
end

RSpec.describe Pipeforge::RunProcessor::FailedRow do
  let(:schema_error_on_email) do
    Pipeforge::ErrorCatalog::ERRORS.fetch(:value_missing).call(origin: :schema, target_column_name: "email", value: nil)
  end
  let(:model_error_on_name) do
    Pipeforge::ErrorCatalog::ERRORS.fetch(:value_invalid).call(
      origin: :model, target_column_name: "name", value: "n", native_message: "is invalid", error_type: :invalid
    )
  end

  describe ".new" do
    subject(:failed_row) do
      described_class.new(row_number: 7, attributes: {"email" => nil}, errors: [schema_error_on_email])
    end

    context "when row_number is 7, attributes is a Hash and errors is a list of one error" do
      # contract only
      it "holds row_number as it was given" do
        expect(failed_row.row_number).to eq(7)
      end

      # contract only
      it "holds attributes as they were given" do
        expect(failed_row.attributes).to eq({"email" => nil})
      end

      # contract only
      it "holds errors as they were given" do
        expect(failed_row.errors).to eq([schema_error_on_email])
      end
    end
  end

  describe "#to_h" do
    describe "the promised contract" do
      context "when the failed row has a row_number, attributes and errors" do
        subject(:failed_row_hash) do
          described_class.new(row_number: 7, attributes: {"email" => nil}, errors: [schema_error_on_email]).to_h
        end

        # contract only
        it "gives a Hash with the keys row_number, attributes and errors" do
          expect(failed_row_hash.keys).to eq(%i[row_number attributes errors])
        end
      end
    end

    describe "the row number and the attributes" do
      context "when the failed row has row_number 7 and attributes with two columns" do
        subject(:failed_row_hash) do
          described_class.new(row_number: 7, attributes: {"id" => nil, "email" => "a"}, errors: [schema_error_on_email]).to_h
        end

        it "gives them as they are" do
          expect(failed_row_hash.slice(:row_number, :attributes)).to eq(row_number: 7, attributes: {"id" => nil, "email" => "a"})
        end
      end
    end

    describe "the errors" do
      context "when the failed row has two errors" do
        subject(:failed_row_hash) do
          described_class.new(row_number: 1, attributes: {}, errors: [schema_error_on_email, model_error_on_name]).to_h
        end

        let(:hash_of_the_schema_error) do
          {
            origin: :schema, code: :value_missing, kind: nil, target_column_name: "email",
            message: "email: the value is required but empty", details: {}, value: nil
          }
        end
        let(:hash_of_the_model_error) do
          {
            origin: :model, code: :value_invalid, kind: nil, target_column_name: "name",
            message: "name: the model does not accept the value (is invalid)",
            details: {native_message: "is invalid", error_type: :invalid}, value: "n"
          }
        end

        it "gives each error as the Hash of its seven fields, in the same order" do
          expect(failed_row_hash[:errors]).to eq([hash_of_the_schema_error, hash_of_the_model_error])
        end
      end

      context "when the failed row has one error" do
        subject(:failed_row_hash) do
          described_class.new(row_number: 1, attributes: {}, errors: [schema_error_on_email]).to_h
        end

        let(:hash_of_the_schema_error) do
          {
            origin: :schema, code: :value_missing, kind: nil, target_column_name: "email",
            message: "email: the value is required but empty", details: {}, value: nil
          }
        end

        it "gives that one Hash" do
          expect(failed_row_hash[:errors]).to eq([hash_of_the_schema_error])
        end
      end

      context "when the failed row has no error" do
        subject(:failed_row_hash) { described_class.new(row_number: 1, attributes: {}, errors: []).to_h }

        it "gives an empty Array" do
          expect(failed_row_hash[:errors]).to eq([])
        end
      end
    end

    context "when to_h was called on a failed row with two errors" do
      subject(:failed_row) do
        described_class.new(row_number: 1, attributes: {}, errors: errors_of_the_failed_row)
      end

      let(:errors_of_the_failed_row) { [schema_error_on_email, model_error_on_name] }

      before { failed_row.to_h }

      it "leaves the errors of the failed row as the error objects" do
        expect(failed_row.errors).to equal(errors_of_the_failed_row)
      end
    end

    describe "collaboration" do
      describe "with the real ErrorCatalog" do
        context "when the errors are built by the ErrorCatalog" do
          subject(:failed_row_hash) do
            described_class.new(row_number: 1, attributes: {}, errors: [schema_error_on_email, model_error_on_name]).to_h
          end

          let(:hashes_of_the_errors) { [schema_error_on_email.to_h, model_error_on_name.to_h] }

          it "gives each Hash as the to_h of the error gives it" do
            expect(failed_row_hash[:errors]).to eq(hashes_of_the_errors)
          end
        end
      end
    end
  end
end
