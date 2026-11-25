# frozen_string_literal: true

# The source column names ("Mail", "Name") differ from the target column names ("email", "name"), so a read under the
# wrong key shows.
RSpec.describe Pipeforge::RunProcessor do
  let(:events) { [] }
  let(:chunk_results_received) { [] }
  let(:scripted_target) do
    target = instance_double(Pipeforge::ActiveRecordTarget)
    allow(target).to receive(:transaction) do |rollback_at_end:, &block|
      events << [:transaction_opened, rollback_at_end]
      block_answer = block.call
      events << :transaction_closed
      block_answer
    end
    target
  end

  def script_reader(chunks:)
    reader = instance_double(Pipeforge::Source::CsvReader)
    allow(reader).to receive(:each_chunk) do |**_keywords, &block|
      chunks.each do |rows|
        events << :chunk_read
        block.call(rows)
      end
    end
    reader
  end

  def script_chunk_processor(chunk_results_by_rows:)
    allow(Pipeforge::RunProcessor::ChunkProcessor).to receive(:call) do |rows:, **_keywords|
      events << :chunk_processed
      chunk_results_by_rows.fetch(rows)
    end
  end

  def script_transformer_and_schema_checker
    allow(Pipeforge::RunProcessor::RowTransformer).to receive(:new)
      .and_return(instance_double(Pipeforge::RunProcessor::RowTransformer))
    allow(Pipeforge::RunProcessor::SchemaChecker).to receive(:new)
      .and_return(instance_double(Pipeforge::RunProcessor::SchemaChecker))
  end

  def run_all(source_reader:, mode:, resolved_mapped_columns: {}, offset: 0, chunk_size: 2, target: scripted_target, &on_chunk)
    described_class.call(
      source_reader: source_reader, resolved_mapped_columns: resolved_mapped_columns, offset: offset,
      chunk_size: chunk_size, mode: mode, target: target, &on_chunk
    )
  end

  def run_all_collecting_chunk_results(**keywords)
    run_all(**keywords) { |chunk_result| chunk_results_received << chunk_result }
  end

  def schema_value_missing_on(target_column_name:)
    Pipeforge::ErrorCatalog::ERRORS.fetch(:value_missing).call(
      origin: :schema, target_column_name: target_column_name, value: nil
    )
  end

  def model_error_on(target_column_name:, value:)
    Pipeforge::ErrorCatalog::ERRORS.fetch(:value_invalid).call(
      origin: :model, target_column_name: target_column_name, value: value, native_message: "is invalid", error_type: :invalid
    )
  end

  shared_context "with three chunks" do
    let(:first_chunk) { [{"Mail" => "a"}, {"Mail" => "b"}] }
    let(:second_chunk) { [{"Mail" => "c"}, {"Mail" => "d"}] }
    let(:third_chunk) { [{"Mail" => "e"}] }
    let(:three_chunks) { [first_chunk, second_chunk, third_chunk] }
    let(:chunk_result_of_first_chunk) do
      Pipeforge::RunProcessor::ChunkResult.new(
        first_row_number: 1, last_row_number: 2, processed_rows_count: 2, valid_rows_count: 2, failed_rows_count: 0,
        failed_rows: []
      )
    end
    let(:chunk_result_of_second_chunk) do
      Pipeforge::RunProcessor::ChunkResult.new(
        first_row_number: 3, last_row_number: 4, processed_rows_count: 2, valid_rows_count: 1, failed_rows_count: 1,
        failed_rows: [
          Pipeforge::RunProcessor::FailedRow.new(
            row_number: 4, attributes: {"email" => "d"}, errors: [schema_value_missing_on(target_column_name: "email")]
          )
        ]
      )
    end
    let(:chunk_result_of_third_chunk) do
      Pipeforge::RunProcessor::ChunkResult.new(
        first_row_number: 5, last_row_number: 5, processed_rows_count: 1, valid_rows_count: 0, failed_rows_count: 1,
        failed_rows: [
          Pipeforge::RunProcessor::FailedRow.new(
            row_number: 5, attributes: {"email" => "e"}, errors: [schema_value_missing_on(target_column_name: "email")]
          )
        ]
      )
    end
    let(:chunk_results_of_three_chunks) do
      [chunk_result_of_first_chunk, chunk_result_of_second_chunk, chunk_result_of_third_chunk]
    end
    let(:run_result_of_three_chunks) do
      Pipeforge::RunProcessor::RunResult.new(processed_rows_count: 5, valid_rows_count: 3, failed_rows_count: 2)
    end
    let(:reader_of_three_chunks) { script_reader(chunks: three_chunks) }

    before do
      script_chunk_processor(
        chunk_results_by_rows: {
          first_chunk => chunk_result_of_first_chunk,
          second_chunk => chunk_result_of_second_chunk,
          third_chunk => chunk_result_of_third_chunk
        }
      )
    end
  end

  describe ".call" do
    describe "the promised contract" do
      context "when the reader yields one chunk whose chunk result counts 3 processed, 2 valid and 1 failed" do
        subject(:run_result) { run_all(source_reader: reader_of_one_chunk, mode: :run) }

        let(:one_chunk) { [{"Mail" => "a"}, {"Mail" => "b"}, {"Mail" => "c"}] }
        let(:chunk_result_of_one_chunk) do
          Pipeforge::RunProcessor::ChunkResult.new(
            first_row_number: 1, last_row_number: 3, processed_rows_count: 3, valid_rows_count: 2, failed_rows_count: 1,
            failed_rows: [
              Pipeforge::RunProcessor::FailedRow.new(
                row_number: 3, attributes: {"email" => "c"}, errors: [schema_value_missing_on(target_column_name: "email")]
              )
            ]
          )
        end
        let(:reader_of_one_chunk) { script_reader(chunks: [one_chunk]) }
        let(:run_result_of_one_chunk) do
          Pipeforge::RunProcessor::RunResult.new(processed_rows_count: 3, valid_rows_count: 2, failed_rows_count: 1)
        end

        before do
          script_transformer_and_schema_checker
          script_chunk_processor(chunk_results_by_rows: {one_chunk => chunk_result_of_one_chunk})
        end

        it "gives a RunResult with processed_rows_count, valid_rows_count and failed_rows_count" do
          expect(run_result).to eq(run_result_of_one_chunk)
        end
      end
    end

    describe "the behaviours" do
      before { script_transformer_and_schema_checker }

      describe "the totals" do
        context "when the reader yields three chunks whose chunk results count (2 processed, 2 valid, 0 failed), (2, 1, 1) and (1, 0, 1)" do
          include_context "with three chunks"

          subject(:run_result) { run_all(source_reader: reader_of_three_chunks, mode: :run) }

          it "gives 5 as processed_rows_count, 3 as valid_rows_count and 2 as failed_rows_count" do
            expect(run_result).to eq(run_result_of_three_chunks)
          end
        end

        context "when the reader yields no chunk" do
          subject(:run_result) { run_all_collecting_chunk_results(source_reader: reader_with_no_chunk, mode: :run) }

          let(:reader_with_no_chunk) { script_reader(chunks: []) }
          let(:run_result_of_no_chunk) do
            Pipeforge::RunProcessor::RunResult.new(processed_rows_count: 0, valid_rows_count: 0, failed_rows_count: 0)
          end

          it "gives 0 as processed_rows_count, as valid_rows_count and as failed_rows_count" do
            expect(run_result).to eq(run_result_of_no_chunk)
          end

          it "does not call the block" do
            run_result
            expect(chunk_results_received).to eq([])
          end
        end
      end

      describe "the block" do
        context "when the reader yields three chunks and a block is given" do
          include_context "with three chunks"

          subject(:run_result) do
            run_all(source_reader: reader_of_three_chunks, mode: :run) do |chunk_result|
              chunk_results_received << chunk_result
              events << :block
            end
          end

          let(:events_of_three_chunks) do
            [:chunk_read, :chunk_processed, :block, :chunk_read, :chunk_processed, :block, :chunk_read, :chunk_processed, :block]
          end

          it "gives the block each chunk result as the chunk processor gave it, in order" do
            run_result
            expect(chunk_results_received).to eq(chunk_results_of_three_chunks)
          end

          it "gives the block the chunk result of a chunk before the next chunk is read" do
            run_result
            expect(events).to eq(events_of_three_chunks)
          end
        end

        context "when no block is given" do
          include_context "with three chunks"

          subject(:run_result) { run_all(source_reader: reader_of_three_chunks, mode: :run) }

          it "gives the run result" do
            expect(run_result).to eq(run_result_of_three_chunks)
          end
        end
      end

      describe "mode" do
        context "when mode is :dry_run" do
          include_context "with three chunks"

          subject(:run_result) { run_all(source_reader: reader_of_three_chunks, mode: :dry_run) }

          let(:events_inside_one_transaction) do
            [
              [:transaction_opened, true],
              :chunk_read, :chunk_processed, :chunk_read, :chunk_processed, :chunk_read, :chunk_processed,
              :transaction_closed
            ]
          end

          it "opens one transaction with rollback_at_end true and processes every chunk inside it" do
            run_result
            expect(events).to eq(events_inside_one_transaction)
          end

          it "gives the run result of the chunks" do
            expect(run_result).to eq(run_result_of_three_chunks)
          end

          context "and a block is given" do
            subject(:run_result) do
              run_all(source_reader: reader_of_three_chunks, mode: :dry_run) { events << :block }
            end

            let(:events_with_the_block_inside_the_transaction) do
              [
                [:transaction_opened, true],
                :chunk_read, :chunk_processed, :block, :chunk_read, :chunk_processed, :block,
                :chunk_read, :chunk_processed, :block,
                :transaction_closed
              ]
            end

            it "calls the block inside the transaction" do
              run_result
              expect(events).to eq(events_with_the_block_inside_the_transaction)
            end
          end
        end

        context "when mode is :run" do
          include_context "with three chunks"

          subject(:run_result) { run_all(source_reader: reader_of_three_chunks, mode: :run) }

          let(:events_with_no_transaction) do
            [:chunk_read, :chunk_processed, :chunk_read, :chunk_processed, :chunk_read, :chunk_processed]
          end

          it "opens no transaction" do
            run_result
            expect(events).to eq(events_with_no_transaction)
          end

          it "gives the run result of the chunks" do
            expect(run_result).to eq(run_result_of_three_chunks)
          end
        end

        context "when the same three chunks are processed in a dry run and in a run" do
          include_context "with three chunks"

          let(:run_result_of_a_dry_run) { run_all(source_reader: reader_of_three_chunks, mode: :dry_run) }
          let(:run_result_of_a_run) { run_all(source_reader: reader_of_three_chunks, mode: :run) }

          it "gives the same run result in both" do
            expect(run_result_of_a_dry_run).to eq(run_result_of_a_run)
          end
        end
      end
      describe "a failure of the reader" do
        context "when the reader raises a Source::Error while it reads" do
          subject(:run_call) { run_all(source_reader: reader_that_raises, mode: :run) }

          let(:error_of_the_reader) { Pipeforge::Source::Error.single(code: :malformed_row, message: "malformed CSV at line 3", line: 3) }
          let(:reader_that_raises) do
            reader = instance_double(Pipeforge::Source::CsvReader)
            allow(reader).to receive(:each_chunk).and_raise(error_of_the_reader)
            reader
          end

          it "raises that error" do
            expect { run_call }.to raise_error(error_of_the_reader)
          end
        end
      end
    end

    describe "collaboration" do
      describe "with the real source reader" do
        context "when three target columns read Mail, Mail and Zip, offset is 1 and chunk_size is 2" do
          subject(:run_result) do
            run_all(
              source_reader: real_reader, resolved_mapped_columns: resolved_mapped_columns_of_mail_and_zip,
              offset: 1, chunk_size: 2, mode: :run
            )
          end

          let(:csv_of_five_rows) do
            <<~CSV
              Mail,State,Zip
              a@example.com,ok,10001
              b@example.com,ok,10002
              c@example.com,ok,10003
              d@example.com,ok,10004
              e@example.com,ok,10005
            CSV
          end
          let(:real_reader) { csv_reader(csv_of_five_rows) }
          let(:resolved_mapped_columns_of_mail_and_zip) do
            resolve_mapped_columns(
              "email" => {source_column_name: "Mail"}, "contact_email" => {source_column_name: "Mail"},
              "zip" => {source_column_name: "Zip"}
            )
          end
          let(:chunk_after_the_offset) { [{"Mail" => "b@example.com", "Zip" => "10002"}, {"Mail" => "c@example.com", "Zip" => "10003"}] }
          let(:last_chunk) { [{"Mail" => "d@example.com", "Zip" => "10004"}, {"Mail" => "e@example.com", "Zip" => "10005"}] }
          let(:chunk_result_after_the_offset) do
            Pipeforge::RunProcessor::ChunkResult.new(
              first_row_number: 2, last_row_number: 3, processed_rows_count: 2, valid_rows_count: 2, failed_rows_count: 0,
              failed_rows: []
            )
          end
          let(:chunk_result_of_the_last_chunk) do
            Pipeforge::RunProcessor::ChunkResult.new(
              first_row_number: 4, last_row_number: 5, processed_rows_count: 2, valid_rows_count: 1, failed_rows_count: 1,
              failed_rows: [
                Pipeforge::RunProcessor::FailedRow.new(
                  row_number: 5, attributes: {"email" => "e@example.com"},
                  errors: [schema_value_missing_on(target_column_name: "zip")]
                )
              ]
            )
          end
          let(:run_result_of_the_two_chunks) do
            Pipeforge::RunProcessor::RunResult.new(processed_rows_count: 4, valid_rows_count: 3, failed_rows_count: 1)
          end

          before do
            script_transformer_and_schema_checker
            allow(real_reader).to receive(:each_chunk).and_call_original
            script_chunk_processor(
              chunk_results_by_rows: {
                chunk_after_the_offset => chunk_result_after_the_offset,
                last_chunk => chunk_result_of_the_last_chunk
              }
            )
          end

          it "asks the reader for the chunks with offset, chunk_size and each source column once" do
            run_result
            expect(real_reader).to have_received(:each_chunk).with(offset: 1, chunk_size: 2, columns: %w[Mail Zip])
          end

          it "gives each chunk the reader yields as the rows of a call of the chunk processor" do
            run_result
            expect(Pipeforge::RunProcessor::ChunkProcessor).to have_received(:call)
              .with(hash_including(rows: chunk_after_the_offset))
            expect(Pipeforge::RunProcessor::ChunkProcessor).to have_received(:call)
              .with(hash_including(rows: last_chunk))
          end

          it "adds up the chunk results of the chunks the reader yielded" do
            expect(run_result).to eq(run_result_of_the_two_chunks)
          end
        end
      end

      describe "with the real transformer and the real schema checker" do
        context "when the reader yields three chunks" do
          include_context "with three chunks"

          subject(:run_result) do
            run_all(
              source_reader: reader_of_three_chunks, resolved_mapped_columns: resolved_mapped_columns_of_mail,
              mode: :run
            )
          end

          let(:resolved_mapped_columns_of_mail) { resolve_mapped_columns("email" => {source_column_name: "Mail"}) }
          let(:built_transformers) { [] }
          let(:built_schema_checkers) { [] }

          before do
            allow(Pipeforge::RunProcessor::RowTransformer).to receive(:new).and_wrap_original do |new, **keywords|
              new.call(**keywords).tap { |transformer| built_transformers << transformer }
            end
            allow(Pipeforge::RunProcessor::SchemaChecker).to receive(:new).and_wrap_original do |new, **keywords|
              new.call(**keywords).tap { |schema_checker| built_schema_checkers << schema_checker }
            end
            run_result
          end

          it "builds one transformer from the resolved mapped columns" do
            expect(Pipeforge::RunProcessor::RowTransformer).to have_received(:new)
              .with(resolved_mapped_columns: resolved_mapped_columns_of_mail).once
          end

          it "builds one schema checker from the resolved mapped columns" do
            expect(Pipeforge::RunProcessor::SchemaChecker).to have_received(:new)
              .with(resolved_mapped_columns: resolved_mapped_columns_of_mail).once
          end

          it "gives that transformer and that schema checker to the chunk processor for every chunk" do
            expect(Pipeforge::RunProcessor::ChunkProcessor).to have_received(:call)
              .with(hash_including(transformer: built_transformers.first, schema_checker: built_schema_checkers.first))
              .exactly(3).times
          end
        end
      end

      describe "with the real chunk processor and the real target and model" do
        context "when the model validates the format of email and the reader yields five rows in chunks of two" do
          subject(:run_result) do
            run_all_collecting_chunk_results(
              source_reader: reader_of_five_rows, resolved_mapped_columns: resolved_mapped_columns_of_mail,
              offset: 1, chunk_size: 2, mode: mode, target: real_target
            )
          end

          let(:model_that_validates_the_format_of_email) do
            define_model(name: "ModelThatValidatesTheFormatOfEmail", columns: ->(table) { table.string :email }) do
              validates :email, format: {with: /@/}
            end
          end
          let(:real_target) { Pipeforge::ActiveRecordTarget.new(target_model_name: model_that_validates_the_format_of_email.name) }
          let(:resolved_mapped_columns_of_mail) { resolve_mapped_columns("email" => {source_column_name: "Mail"}) }
          let(:first_chunk) { [{"Mail" => "a@example.com"}, {"Mail" => "b@example.com"}] }
          let(:second_chunk) { [{"Mail" => "c@example.com"}, {"Mail" => "no-at-sign"}] }
          let(:third_chunk) { [{"Mail" => "e@example.com"}] }
          let(:reader_of_five_rows) { script_reader(chunks: [first_chunk, second_chunk, third_chunk]) }
          let(:chunk_results_of_five_rows) do
            [
              Pipeforge::RunProcessor::ChunkResult.new(
                first_row_number: 2, last_row_number: 3, processed_rows_count: 2, valid_rows_count: 2, failed_rows_count: 0,
                failed_rows: []
              ),
              Pipeforge::RunProcessor::ChunkResult.new(
                first_row_number: 4, last_row_number: 5, processed_rows_count: 2, valid_rows_count: 1, failed_rows_count: 1,
                failed_rows: [
                  Pipeforge::RunProcessor::FailedRow.new(
                    row_number: 5, attributes: {"id" => nil, "email" => "no-at-sign"},
                    errors: [model_error_on(target_column_name: "email", value: "no-at-sign")]
                  )
                ]
              ),
              Pipeforge::RunProcessor::ChunkResult.new(
                first_row_number: 6, last_row_number: 6, processed_rows_count: 1, valid_rows_count: 1, failed_rows_count: 0,
                failed_rows: []
              )
            ]
          end

          before { allow(Pipeforge::RunProcessor::ChunkProcessor).to receive(:call).and_call_original }

          context "and mode is :run" do
            let(:mode) { :run }
            let(:run_result_of_five_rows) do
              Pipeforge::RunProcessor::RunResult.new(processed_rows_count: 5, valid_rows_count: 4, failed_rows_count: 1)
            end

            it "gives each call of the chunk processor the first row number of its chunk" do
              run_result
              expect(Pipeforge::RunProcessor::ChunkProcessor).to have_received(:call)
                .with(hash_including(rows: first_chunk, first_row_number: 2, target: real_target))
              expect(Pipeforge::RunProcessor::ChunkProcessor).to have_received(:call)
                .with(hash_including(rows: second_chunk, first_row_number: 4, target: real_target))
              expect(Pipeforge::RunProcessor::ChunkProcessor).to have_received(:call)
                .with(hash_including(rows: third_chunk, first_row_number: 6, target: real_target))
            end

            it "gives the block the chunk results, with the failed row under its row number in the source" do
              run_result
              expect(chunk_results_received).to eq(chunk_results_of_five_rows)
            end

            it "gives the run result of the five rows" do
              expect(run_result).to eq(run_result_of_five_rows)
            end

            it "keeps the rows that passed in the table" do
              run_result
              expect(model_that_validates_the_format_of_email.order(:id).pluck(:email)).to eq(
                %w[a@example.com b@example.com c@example.com e@example.com]
              )
            end
          end

          context "and mode is :dry_run" do
            let(:mode) { :dry_run }

            it "gives the block the same chunk results as a run" do
              run_result
              expect(chunk_results_received).to eq(chunk_results_of_five_rows)
            end

            it "leaves the table empty" do
              run_result
              expect(model_that_validates_the_format_of_email.pluck(:email)).to eq([])
            end
          end
        end

        context "when the reader yields a chunk and then raises a Source::Error" do
          subject(:run_result) do
            run_all(
              source_reader: reader_that_fails_in_the_second_chunk,
              resolved_mapped_columns: resolved_mapped_columns_of_mail, mode: mode, target: real_target
            )
          end

          let(:model_of_two_emails) do
            define_model(name: "ModelOfTwoEmails", columns: ->(table) { table.string :email })
          end
          let(:real_target) { Pipeforge::ActiveRecordTarget.new(target_model_name: model_of_two_emails.name) }
          let(:resolved_mapped_columns_of_mail) { resolve_mapped_columns("email" => {source_column_name: "Mail"}) }
          let(:error_of_the_reader) { Pipeforge::Source::Error.single(code: :malformed_row, message: "malformed CSV at line 4", line: 4) }
          let(:reader_that_fails_in_the_second_chunk) do
            reader = instance_double(Pipeforge::Source::CsvReader)
            allow(reader).to receive(:each_chunk) do |**_keywords, &block|
              block.call([{"Mail" => "a@example.com"}, {"Mail" => "b@example.com"}])
              raise error_of_the_reader
            end
            reader
          end

          def run_and_ignore_the_error
            run_result
          rescue Pipeforge::Source::Error
            nil
          end

          context "and mode is :dry_run" do
            let(:mode) { :dry_run }

            it "raises that error" do
              expect { run_result }.to raise_error(error_of_the_reader)
            end

            # The first chunk was written inside the transaction, which is rolled back when the error comes out.
            it "keeps the rows of the first chunk out of the table" do
              run_and_ignore_the_error
              expect(model_of_two_emails.pluck(:email)).to eq([])
            end
          end

          context "and mode is :run" do
            let(:mode) { :run }

            it "raises that error" do
              expect { run_result }.to raise_error(error_of_the_reader)
            end

            it "keeps the rows of the first chunk in the table" do
              run_and_ignore_the_error
              expect(model_of_two_emails.order(:id).pluck(:email)).to eq(%w[a@example.com b@example.com])
            end
          end
        end
      end

      describe "with all the real collaborators" do
        context "when the CSV has five rows, row 2 with an empty Name and row 3 with an email the model refuses, and chunk_size is 2" do
          subject(:run_result) do
            run_all_collecting_chunk_results(
              source_reader: csv_reader(csv_of_five_rows), resolved_mapped_columns: resolved_mapped_columns_of_mail_and_name,
              chunk_size: 2, mode: mode, target: real_target
            )
          end

          let(:csv_of_five_rows) do
            <<~CSV
              Mail,Name
              ann@example.com,Ann
              bob@example.com,
              no-at-sign,Cy
              dee@example.com,Dee
              eve@example.com,Eve
            CSV
          end
          let(:model_with_a_format_on_email) do
            define_model(
              name: "ModelWithAFormatOnEmail",
              columns: ->(table) {
                table.string :email
                table.string :name
              }
            ) do
              validates :email, format: {with: /@/}
            end
          end
          let(:real_target) { Pipeforge::ActiveRecordTarget.new(target_model_name: model_with_a_format_on_email.name) }
          let(:resolved_mapped_columns_of_mail_and_name) do
            resolve_mapped_columns_of(
              target_columns: [build_target_column(name: "email"), build_target_column(name: "name", required: true)],
              mapped_columns: {"email" => {source_column_name: "Mail"}, "name" => {source_column_name: "Name"}}
            )
          end
          let(:run_result_of_five_rows) do
            Pipeforge::RunProcessor::RunResult.new(processed_rows_count: 5, valid_rows_count: 3, failed_rows_count: 2)
          end
          let(:chunk_results_of_five_rows) do
            [
              Pipeforge::RunProcessor::ChunkResult.new(
                first_row_number: 1, last_row_number: 2, processed_rows_count: 2, valid_rows_count: 1, failed_rows_count: 1,
                failed_rows: [
                  Pipeforge::RunProcessor::FailedRow.new(
                    row_number: 2, attributes: {"id" => nil, "email" => "bob@example.com", "name" => nil},
                    errors: [schema_value_missing_on(target_column_name: "name")]
                  )
                ]
              ),
              Pipeforge::RunProcessor::ChunkResult.new(
                first_row_number: 3, last_row_number: 4, processed_rows_count: 2, valid_rows_count: 1, failed_rows_count: 1,
                failed_rows: [
                  Pipeforge::RunProcessor::FailedRow.new(
                    row_number: 3, attributes: {"id" => nil, "email" => "no-at-sign", "name" => "Cy"},
                    errors: [model_error_on(target_column_name: "email", value: "no-at-sign")]
                  )
                ]
              ),
              Pipeforge::RunProcessor::ChunkResult.new(
                first_row_number: 5, last_row_number: 5, processed_rows_count: 1, valid_rows_count: 1, failed_rows_count: 0,
                failed_rows: []
              )
            ]
          end

          context "and mode is :dry_run" do
            let(:mode) { :dry_run }

            it "gives the run result of the five rows" do
              expect(run_result).to eq(run_result_of_five_rows)
            end

            it "gives the block the chunk results, in three chunks with the failed rows and their errors" do
              run_result
              expect(chunk_results_received).to eq(chunk_results_of_five_rows)
            end

            it "leaves the table empty" do
              run_result
              expect(model_with_a_format_on_email.pluck(:email, :name)).to eq([])
            end
          end

          context "and mode is :run" do
            let(:mode) { :run }

            it "gives the run result of the five rows" do
              expect(run_result).to eq(run_result_of_five_rows)
            end

            it "gives the block the chunk results, in three chunks with the failed rows and their errors" do
              run_result
              expect(chunk_results_received).to eq(chunk_results_of_five_rows)
            end

            it "keeps the three rows that passed in the table" do
              run_result
              expect(model_with_a_format_on_email.order(:id).pluck(:email, :name)).to eq(
                [["ann@example.com", "Ann"], ["dee@example.com", "Dee"], ["eve@example.com", "Eve"]]
              )
            end
          end
        end
      end
    end
  end
end
