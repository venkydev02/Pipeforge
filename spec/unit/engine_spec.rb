# frozen_string_literal: true

RSpec.shared_context "with the real collaborators of the engine spied" do
  let(:reusable_ios) { [] }
  let(:source_readers) { [] }
  let(:targets) { [] }
  let(:target_schemas) { [] }
  let(:resolved_mappings) { [] }
  let(:header_analyses) { [] }
  let(:value_analyses) { [] }
  let(:run_results) { [] }
  let(:blocks_given_to_run_processor) { [] }

  before do
    allow(Pipeforge::Source::ReusableIO).to receive(:new).and_wrap_original do |original, **arguments|
      reusable_ios << original.call(**arguments)
      reusable_ios.last
    end

    allow(Pipeforge::Source::CsvReader).to receive(:new).and_wrap_original do |original, **arguments|
      source_reader = original.call(**arguments)
      allow(source_reader).to receive(:headers).and_call_original
      allow(source_reader).to receive(:each_row).and_call_original
      allow(source_reader).to receive(:each_chunk).and_call_original
      source_readers << source_reader
      source_reader
    end

    allow(Pipeforge::ActiveRecordTarget).to receive(:new).and_wrap_original do |original, **arguments|
      target = original.call(**arguments)
      allow(target).to receive(:schema).and_wrap_original do |original_schema|
        target_schemas << original_schema.call
        target_schemas.last
      end
      targets << target
      target
    end

    allow(Pipeforge::MappedColumns).to receive(:new).and_wrap_original do |original, **arguments|
      mapped_columns = original.call(**arguments)
      allow(mapped_columns).to receive(:resolved_mapped_columns!).and_wrap_original do |original_resolution|
        resolved_mappings << original_resolution.call
        resolved_mappings.last
      end
      mapped_columns
    end

    allow(Pipeforge::HeaderAnalyzer).to receive(:call).and_wrap_original do |original, **arguments|
      header_analyses << original.call(**arguments)
      header_analyses.last
    end

    allow(Pipeforge::ColumnValueAnalyzer).to receive(:call).and_wrap_original do |original, **arguments|
      value_analyses << original.call(**arguments)
      value_analyses.last
    end

    allow(Pipeforge::RunProcessor).to receive(:call).and_wrap_original do |original, **arguments, &block|
      blocks_given_to_run_processor << block
      run_results << original.call(**arguments, &block)
      run_results.last
    end
  end
end

RSpec.shared_examples "a refused argument of run" do
  it "raises ArgumentError with the sentence of each argument it refuses" do
    expect { run_result }.to raise_error(ArgumentError, expected_message)
  end
end

RSpec.describe Pipeforge::Engine do
  # The installed class is one for the whole process.
  around do |example|
    installed_class = described_class.target_class
    example.run
  ensure
    described_class.install_target(target_class: installed_class)
  end

  let(:contact_model) do
    define_model(
      name: "EngineSpecContact",
      columns: ->(table) {
        table.string :email
        table.string :nickname
      }
    )
  end
  let(:engine) { described_class.new(source_io: source_io, target_model_name: contact_model.name) }

  describe ".install_target" do
    let(:first_class) { Class.new }
    let(:second_class) { Class.new }

    context "when one target_class is installed" do
      before { described_class.install_target(target_class: first_class) }

      it "gives that class as target_class" do
        expect(described_class.target_class).to be(first_class)
      end
    end

    context "when a second target_class is installed" do
      before do
        described_class.install_target(target_class: first_class)
        described_class.install_target(target_class: second_class)
      end

      it "gives the second class as target_class" do
        expect(described_class.target_class).to be(second_class)
      end
    end
  end

  describe ".new" do
    subject(:building) { described_class.new(source_io: source_io, target_model_name: target_model_name) }

    context "when the source has a usable header and the model exists" do
      let(:source_io) { csv_io("Mail,Age\n") }
      let(:target_model_name) { contact_model.name }

      it "gives an Engine" do
        expect(building).to be_an_instance_of(described_class)
      end
    end

    context "when the source does not respond to rewind" do
      let(:source_io) do
        Class.new do
          def read(*)
          end

          def seek(*)
          end
        end.new
      end
      let(:target_model_name) { contact_model.name }
      let(:expected_message) do
        argument_message(:source_missing_methods, required_method_names: %i[read rewind seek], missing_method_names: %i[rewind])
      end

      before { allow(Pipeforge::ActiveRecordTarget).to receive(:new).and_call_original }

      it "raises ArgumentError naming rewind" do
        expect { building }.to raise_error(ArgumentError, expected_message)
      end

      it "builds no target" do
        expect { building }.to raise_error(ArgumentError)
        expect(Pipeforge::ActiveRecordTarget).not_to have_received(:new)
      end
    end

    context "when no loaded model is named target_model_name" do
      let(:source_io) { csv_io("Mail,Age\n") }
      let(:target_model_name) { "AdapterSpecModels::NoSuchModel" }

      it "raises TargetSchemaError" do
        expect { building }.to raise_error(Pipeforge::TargetSchemaError)
      end
    end

    describe "collaboration" do
      include_context "with the real collaborators of the engine spied"

      context "when the source has a usable header and the model exists" do
        let(:source_io) { csv_io("Mail,Age\na@example.com,3\n") }
        let(:target_model_name) { contact_model.name }

        before { building }

        it "wraps the source in a ReusableIO" do
          expect(Pipeforge::Source::ReusableIO).to have_received(:new).with(io: source_io)
        end

        it "builds a CsvReader on that ReusableIO" do
          expect(Pipeforge::Source::CsvReader).to have_received(:new).with(source_io: equal(reusable_ios.first))
        end

        it "reads the headers" do
          expect(source_readers.first).to have_received(:headers)
        end

        it "builds the target for target_model_name" do
          expect(Pipeforge::ActiveRecordTarget).to have_received(:new).with(target_model_name: target_model_name)
        end

        it "reads the schema of the target once" do
          expect(targets.first).to have_received(:schema).once
        end

        it "reads no row" do
          expect(source_readers.first).not_to have_received(:each_row)
          expect(source_readers.first).not_to have_received(:each_chunk)
        end

        it "calls no stage" do
          expect(Pipeforge::HeaderAnalyzer).not_to have_received(:call)
          expect(Pipeforge::ColumnValueAnalyzer).not_to have_received(:call)
          expect(Pipeforge::RunProcessor).not_to have_received(:call)
        end
      end

      context "when the source is empty" do
        let(:source_io) { csv_io("") }
        let(:target_model_name) { contact_model.name }

        it "raises Source::Error" do
          expect { building }.to raise_error(Pipeforge::Source::Error)
        end

        it "reads the headers" do
          expect { building }.to raise_error(Pipeforge::Source::Error)
          expect(source_readers.first).to have_received(:headers)
        end

        it "builds no target" do
          expect { building }.to raise_error(Pipeforge::Source::Error)
          expect(Pipeforge::ActiveRecordTarget).not_to have_received(:new)
        end
      end
    end
  end

  describe "#analyze_headers" do
    subject(:header_analysis) { engine.analyze_headers }

    include_context "with the real collaborators of the engine spied"

    context "when the engine is built" do
      let(:source_io) { csv_io("Mail,Age\na@example.com,3\n") }

      before { header_analysis }

      it "calls HeaderAnalyzer with the headers and the schema read when the engine was built" do
        expect(Pipeforge::HeaderAnalyzer).to have_received(:call)
          .with(source_headers: %w[Mail Age], target_schema: equal(target_schemas.first))
      end

      it "builds no other target" do
        expect(Pipeforge::ActiveRecordTarget).to have_received(:new).once
      end

      it "does not read the schema again" do
        expect(targets.first).to have_received(:schema).once
      end

      it "reads no row" do
        expect(source_readers.first).not_to have_received(:each_row)
        expect(source_readers.first).not_to have_received(:each_chunk)
      end

      it "gives the very result of HeaderAnalyzer" do
        expect(header_analysis).to equal(header_analyses.first)
      end
    end
  end

  describe "#analyze_column_values" do
    subject(:value_analysis) { engine.analyze_column_values(mapped_columns: mapped_columns) }

    include_context "with the real collaborators of the engine spied"

    context "when the mapped columns fit the file and the table" do
      let(:source_io) { csv_io("Mail,Age\na@example.com,3\n") }
      let(:mapped_columns) { {email: {source_column_name: "Mail"}} }

      before { value_analysis }

      it "builds MappedColumns with the mapped columns, the headers and the columns of the schema" do
        expect(Pipeforge::MappedColumns).to have_received(:new).with(
          mapped_columns: mapped_columns, source_header_names: %w[Mail Age], target_columns: target_schemas.first.columns
        )
      end

      it "calls ColumnValueAnalyzer with the source reader, the resolved columns and the target" do
        expect(Pipeforge::ColumnValueAnalyzer).to have_received(:call).with(
          source_reader: equal(source_readers.first), resolved_mapped_columns: equal(resolved_mappings.first),
          target: equal(targets.first)
        )
      end

      it "does not call RunProcessor" do
        expect(Pipeforge::RunProcessor).not_to have_received(:call)
      end

      it "gives the very result of ColumnValueAnalyzer" do
        expect(value_analysis).to equal(value_analyses.first)
      end
    end

    context "when a mapped source column is not in the file" do
      let(:source_io) { csv_io("Mail,Age\na@example.com,3\n") }
      let(:mapped_columns) { {email: {source_column_name: "Email address"}} }

      it "raises InvalidMappedColumnsError" do
        expect { value_analysis }.to raise_error(Pipeforge::InvalidMappedColumnsError)
      end

      it "does not call ColumnValueAnalyzer" do
        expect { value_analysis }.to raise_error(Pipeforge::InvalidMappedColumnsError)
        expect(Pipeforge::ColumnValueAnalyzer).not_to have_received(:call)
      end
    end

    context "when mapped_columns is not a Hash" do
      let(:source_io) { csv_io("Mail,Age\na@example.com,3\n") }
      let(:mapped_columns) { ["email"] }

      it "raises ArgumentError saying mapped_columns must be a Hash" do
        expect { value_analysis }.to raise_error(ArgumentError, argument_message(:mapped_columns_not_a_hash, given_class: Array))
      end

      it "does not call ColumnValueAnalyzer" do
        expect { value_analysis }.to raise_error(ArgumentError)
        expect(Pipeforge::ColumnValueAnalyzer).not_to have_received(:call)
      end
    end

    context "when called twice" do
      let(:source_io) { csv_io("Mail,Age\na@example.com,3\n") }
      let(:mapped_columns) { {email: {source_column_name: "Mail"}} }

      before do
        engine.analyze_column_values(mapped_columns: mapped_columns)
        engine.analyze_column_values(mapped_columns: mapped_columns)
      end

      it "builds the target only when the engine is built" do
        expect(Pipeforge::ActiveRecordTarget).to have_received(:new).once
      end

      it "reads the schema only when the engine is built" do
        expect(targets.first).to have_received(:schema).once
      end
    end

    context "when a row has more cells than the header" do
      # The header reader parses the first row too, so the long row comes after it.
      let(:source_io) { csv_io("Mail,Age\na@example.com,3\nb@example.com,4,extra\n") }
      let(:mapped_columns) { {email: {source_column_name: "Mail"}} }

      it "raises Source::Error" do
        expect { value_analysis }.to raise_error(Pipeforge::Source::Error)
      end
    end
  end

  describe "#run" do
    describe "mode, offset and chunk_size" do
      subject(:run_result) { engine.run(mapped_columns: {email: {source_column_name: "Mail"}}, **run_arguments) }

      let(:engine) { described_class.new(source_io: csv_io("Mail\n"), target_model_name: "Contact") }
      let(:source_reader) { instance_double(Pipeforge::Source::CsvReader, headers: ["Mail"]) }
      let(:target_schema) { Pipeforge::TargetSchema.new(table_name: "contacts", model_name: "Contact", columns: []) }
      let(:target) { instance_double(Pipeforge::ActiveRecordTarget, schema: target_schema) }
      let(:mapping) { instance_double(Pipeforge::MappedColumns, resolved_mapped_columns!: {}) }
      let(:processor_result) { instance_double(Pipeforge::RunProcessor::RunResult) }

      before do
        allow(Pipeforge::Source::CsvReader).to receive(:new).and_return(source_reader)
        described_class.install_target(target_class: class_double(Pipeforge::ActiveRecordTarget, new: target))
        allow(Pipeforge::MappedColumns).to receive(:new).and_return(mapping)
        allow(Pipeforge::RunProcessor).to receive(:call).and_return(processor_result)
      end

      context "when mode is :dry_run and the mapped columns fit" do
        let(:run_arguments) { {mode: :dry_run} }

        it "gives the very RunResult of RunProcessor" do
          expect(run_result).to equal(processor_result)
        end
      end

      context "when mode is :commit" do
        let(:run_arguments) { {mode: :commit} }
        let(:expected_message) { argument_message(:mode_not_allowed, mode: :commit) }

        include_examples "a refused argument of run"
      end

      context 'when mode is the String "run"' do
        let(:run_arguments) { {mode: "run"} }
        let(:expected_message) { argument_message(:mode_not_allowed, mode: "run") }

        include_examples "a refused argument of run"
      end

      context "when offset is -1" do
        let(:run_arguments) { {mode: :run, offset: -1} }
        let(:expected_message) { argument_message(:value_not_whole_number_at_least_0, name: "offset", value: -1) }

        include_examples "a refused argument of run"
      end

      context "when chunk_size is 0" do
        let(:run_arguments) { {mode: :run, chunk_size: 0} }
        let(:expected_message) { argument_message(:value_not_whole_number_at_least_1, name: "chunk_size", value: 0) }

        include_examples "a refused argument of run"
      end

      context "when mode, offset and chunk_size are all wrong" do
        let(:run_arguments) { {mode: :commit, offset: -1, chunk_size: 0} }
        let(:expected_message) do
          [
            argument_message(:mode_not_allowed, mode: :commit),
            argument_message(:value_not_whole_number_at_least_0, name: "offset", value: -1),
            argument_message(:value_not_whole_number_at_least_1, name: "chunk_size", value: 0)
          ].join("; ")
        end

        include_examples "a refused argument of run"
      end

      context "when mode is :run, offset is 0 and chunk_size is 1" do
        let(:run_arguments) { {mode: :run, offset: 0, chunk_size: 1} }

        it "accepts them and gives the RunResult" do
          expect(run_result).to equal(processor_result)
        end
      end

      context "when offset and chunk_size are not given and the execution.chunk_size setting is 7" do
        let(:run_arguments) { {mode: :run} }

        before do
          use_settings(execution: {chunk_size: 7})
          run_result
        end

        it "calls RunProcessor with offset 0 and chunk_size 7" do
          expect(Pipeforge::RunProcessor).to have_received(:call).with(hash_including(offset: 0, chunk_size: 7))
        end
      end
    end

    describe "collaboration" do
      include_context "with the real collaborators of the engine spied"

      context "when the arguments and the mapped columns are valid and a block is given" do
        subject(:run_result) do
          engine.run(mode: :dry_run, mapped_columns: mapped_columns, offset: 1, chunk_size: 3) do |chunk_result|
            yielded_chunk_results << chunk_result
          end
        end

        let(:source_io) { csv_io("Mail,Age\na@example.com,3\nb@example.com,4\n") }
        let(:mapped_columns) { {email: {source_column_name: "Mail"}} }
        let(:yielded_chunk_results) { [] }

        before { run_result }

        it "calls RunProcessor with the source reader, the resolved columns, offset, chunk_size, mode and the target" do
          expect(Pipeforge::RunProcessor).to have_received(:call).with(
            source_reader: equal(source_readers.first), resolved_mapped_columns: equal(resolved_mappings.first),
            offset: 1, chunk_size: 3, mode: :dry_run, target: equal(targets.first)
          )
        end

        it "passes the block on, which is given each chunk result" do
          expect(yielded_chunk_results).to contain_exactly(an_instance_of(Pipeforge::RunProcessor::ChunkResult))
        end

        it "calls no other stage" do
          expect(Pipeforge::HeaderAnalyzer).not_to have_received(:call)
          expect(Pipeforge::ColumnValueAnalyzer).not_to have_received(:call)
        end

        it "gives the very RunResult of RunProcessor" do
          expect(run_result).to equal(run_results.first)
        end
      end

      context "when no block is given" do
        subject(:run_result) { engine.run(mode: :dry_run, mapped_columns: mapped_columns) }

        let(:source_io) { csv_io("Mail,Age\na@example.com,3\n") }
        let(:mapped_columns) { {email: {source_column_name: "Mail"}} }

        before { run_result }

        it "calls RunProcessor with no block" do
          expect(blocks_given_to_run_processor).to eq([nil])
        end
      end

      context "when mode is :commit" do
        subject(:run_result) { engine.run(mode: :commit, mapped_columns: mapped_columns) }

        let(:source_io) { csv_io("Mail,Age\na@example.com,3\n") }
        let(:mapped_columns) { {email: {source_column_name: "Mail"}} }

        it "does not build MappedColumns" do
          expect { run_result }.to raise_error(ArgumentError)
          expect(Pipeforge::MappedColumns).not_to have_received(:new)
        end

        it "does not call RunProcessor" do
          expect { run_result }.to raise_error(ArgumentError)
          expect(Pipeforge::RunProcessor).not_to have_received(:call)
        end
      end

      context "when a mapped source column is not in the file" do
        subject(:run_result) { engine.run(mode: :dry_run, mapped_columns: mapped_columns) }

        let(:source_io) { csv_io("Mail,Age\na@example.com,3\n") }
        let(:mapped_columns) { {email: {source_column_name: "Email address"}} }

        it "raises InvalidMappedColumnsError" do
          expect { run_result }.to raise_error(Pipeforge::InvalidMappedColumnsError)
        end

        it "does not call RunProcessor" do
          expect { run_result }.to raise_error(Pipeforge::InvalidMappedColumnsError)
          expect(Pipeforge::RunProcessor).not_to have_received(:call)
        end
      end

      context "when a row has more cells than the header" do
        subject(:run_result) { engine.run(mode: :dry_run, mapped_columns: mapped_columns) }

        # The header reader parses the first row too, so the long row comes after it.
        let(:source_io) { csv_io("Mail,Age\na@example.com,3\nb@example.com,4,extra\n") }
        let(:mapped_columns) { {email: {source_column_name: "Mail"}} }

        it "raises Source::Error" do
          expect { run_result }.to raise_error(Pipeforge::Source::Error)
        end
      end
    end
  end
end
