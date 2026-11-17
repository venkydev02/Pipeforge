# frozen_string_literal: true

# The reader, ColumnSummaryBuilder.new, ColumnLimitsChecker.for and the target are doubles: the analyzer only
# reads the header for the position of each source column, builds a summary builder for each resolved mapped column,
# hands each builder the cell of its source column row after row and collects the summaries into a Result.
# What a summary builder does with a cell belongs to its own spec. An example that documents what the analyzer accepts
# (an empty mapping, a file with no data rows) is kept for that and marked contract only.
RSpec.describe Pipeforge::ColumnValueAnalyzer do
  let(:summary_builder_class) { Pipeforge::ColumnValueAnalyzer::ColumnSummaryBuilder }
  let(:column_summary_class) { Pipeforge::ColumnValueAnalyzer::ColumnSummary }

  describe ".call" do
    subject(:result) do
      described_class.call(
        source_reader: source_reader, resolved_mapped_columns: resolved_mapped_columns, target: target
      )
    end

    let(:source_reader) { instance_double(Pipeforge::Source::CsvReader, identifier: "users.csv") }
    let(:target) { instance_double(Pipeforge::ActiveRecordTarget) }
    let(:header_names) { %w[Mail Age] }
    let(:rows) do
      [
        {"Mail" => "a@example.com", "Age" => "30"},
        {"Mail" => "b@example.com", "Age" => nil},
        {"Mail" => "c@example.com", "Age" => "41"}
      ]
    end

    let(:email_summary) { instance_double(column_summary_class) }
    let(:age_summary) { instance_double(column_summary_class) }
    let(:email_builder) do
      instance_double(summary_builder_class, source_column: "Mail", add_cell: nil, summary: email_summary)
    end
    let(:age_builder) do
      instance_double(summary_builder_class, source_column: "Age", add_cell: nil, summary: age_summary)
    end
    let(:summary_builders) { {"email" => email_builder, "age" => age_builder} }

    let(:email_limits_checker) { instance_double(Pipeforge::ColumnLimitsChecker) }
    let(:age_limits_checker) { instance_double(Pipeforge::ColumnLimitsChecker) }
    let(:limits_checkers) { {"email" => email_limits_checker, "age" => age_limits_checker} }

    let(:value_mapping) { {"30" => 30} }
    let(:email_resolved_mapped_column) do
      Pipeforge::ResolvedMappedColumn.new(
        source_column: "Mail", value_mapping: {}, target_column: build_target_column(name: "email")
      )
    end
    let(:age_resolved_mapped_column) do
      Pipeforge::ResolvedMappedColumn.new(
        source_column: "Age", value_mapping: value_mapping, target_column: build_target_column(name: "age")
      )
    end
    let(:resolved_mapped_columns) { {"age" => age_resolved_mapped_column} }

    before do
      allow(source_reader).to receive(:headers).and_return(header_names)
      allow(source_reader).to receive(:each_row) do |&block|
        rows.each(&block)
        rows.size
      end
      allow(summary_builder_class).to receive(:new) do |target_column:, **|
        summary_builders.fetch(target_column)
      end
      allow(Pipeforge::ColumnLimitsChecker).to receive(:for) do |target_column:|
        limits_checkers.fetch(target_column.name)
      end
    end

    describe "the header" do
      # Contract only: an error of the source is not caught.
      context "when headers raises Pipeforge::Source::EmptySourceError" do
        before do
          allow(source_reader).to receive(:headers).and_raise(
            Pipeforge::Source::EmptySourceError.single(code: :source_empty, message: "the source has no header row")
          )
        end

        it "raises it to the caller" do
          expect { result }.to raise_error(Pipeforge::Source::EmptySourceError)
        end
      end
    end

    describe "the summary builders" do
      context "when there is one resolved mapped column, \"age\" reading \"Age\" with a value_mapping" do
        it "builds the summary builder with what the resolved mapped column and the call give" do
          result

          expect(summary_builder_class).to have_received(:new).once.with(
            target_column: "age", source_column: "Age", position: 2, limits_checker: age_limits_checker,
            value_mapping: value_mapping, target: target
          )
        end
      end

      context "when there are two resolved mapped columns" do
        let(:resolved_mapped_columns) do
          {"email" => email_resolved_mapped_column, "age" => age_resolved_mapped_column}
        end

        it "builds one summary builder and asks ColumnLimitsChecker.for once for each target_column" do
          result

          expect(summary_builder_class).to have_received(:new).with(hash_including(target_column: "email")).once
          expect(summary_builder_class).to have_received(:new).with(hash_including(target_column: "age")).once

          expect(Pipeforge::ColumnLimitsChecker).to have_received(:for)
            .with(target_column: email_resolved_mapped_column.target_column).once
          expect(Pipeforge::ColumnLimitsChecker).to have_received(:for)
            .with(target_column: age_resolved_mapped_column.target_column).once
        end
      end

      # Contract only: an empty mapping is not an error.
      context "when resolved_mapped_columns is empty" do
        let(:resolved_mapped_columns) { {} }

        it "builds no summary builder and asks for no limits checker" do
          result

          expect(summary_builder_class).not_to have_received(:new)
          expect(Pipeforge::ColumnLimitsChecker).not_to have_received(:for)
        end
      end
    end

    describe "the rows" do
      context "when there is one resolved mapped column reading \"Age\"" do
        context "and the file has three rows" do
          # The second row has no cell for "Age" (nil): an empty cell reaches the summary builder.
          it "gives add_cell the cell of \"Age\" of each row, in the order of the file" do
            result

            expect(age_builder).to have_received(:add_cell).with(cell: "30").ordered
            expect(age_builder).to have_received(:add_cell).with(cell: nil).ordered
            expect(age_builder).to have_received(:add_cell).with(cell: "41").ordered
          end
        end
      end

      context "when there are two resolved mapped columns reading \"Mail\" and \"Age\"" do
        let(:resolved_mapped_columns) do
          {"email" => email_resolved_mapped_column, "age" => age_resolved_mapped_column}
        end

        it "gives each summary builder the cell of its own source_column" do
          result

          expect(email_builder).to have_received(:add_cell).with(cell: "a@example.com")
          expect(email_builder).not_to have_received(:add_cell).with(cell: "30")
          expect(age_builder).to have_received(:add_cell).with(cell: "30")
          expect(age_builder).not_to have_received(:add_cell).with(cell: "a@example.com")
        end

        it "reads the file once" do
          result

          expect(source_reader).to have_received(:each_row).once
        end
      end

      # Contract only: a file with a header and no data rows is not an error.
      context "when the file has no data rows" do
        let(:rows) { [] }

        it "gives no summary builder a cell" do
          result

          expect(age_builder).not_to have_received(:add_cell)
        end

        it "still collects the summary" do
          expect(result.column_summaries).to eq("age" => age_summary)
        end
      end
    end

    describe "the result" do
      context "when there are two resolved mapped columns, \"email\" first and \"age\" second" do
        let(:resolved_mapped_columns) do
          {"email" => email_resolved_mapped_column, "age" => age_resolved_mapped_column}
        end

        it "has column_summaries with the summary of each builder, keyed by target column and in that order" do
          expect(result.column_summaries.to_a).to eq([["email", email_summary], ["age", age_summary]])
        end

        it "takes every summary after the last add_cell" do
          events = []
          [email_builder, age_builder].each do |summary_builder|
            allow(summary_builder).to receive(:add_cell) { events << :add_cell }
            allow(summary_builder).to receive(:summary) do
              events << :summary
              nil
            end
          end

          result

          expect(events.index(:summary)).to be > events.rindex(:add_cell)
        end
      end

      context "when each_row answers 3" do
        it "has row_count 3" do
          expect(result.row_count).to eq(3)
        end
      end

      context "when identifier is \"users.csv\"" do
        it "has source_identifier \"users.csv\"" do
          expect(result.source_identifier).to eq("users.csv")
        end
      end

      # Contract only: the row count does not depend on the mapping.
      context "when resolved_mapped_columns is empty" do
        let(:resolved_mapped_columns) { {} }

        it "has empty column_summaries and the row_count of the reader" do
          expect(result.column_summaries).to eq({})
          expect(result.row_count).to eq(3)
        end
      end
    end
  end

  describe "Result#to_h" do
    subject(:hash) do
      described_class::Result.new(
        source_identifier: "users.csv", row_count: 3, column_summaries: column_summaries
      ).to_h
    end

    context "when column_summaries has the summaries of \"a\" and \"b\"" do
      let(:column_summaries) do
        {
          "a" => instance_double(Pipeforge::ColumnValueAnalyzer::ColumnSummary, to_h: {empty_count: 1}),
          "b" => instance_double(Pipeforge::ColumnValueAnalyzer::ColumnSummary, to_h: {empty_count: 2})
        }
      end

      it "writes source_identifier, row_count and the to_h of each summary keyed by target column" do
        expect(hash).to eq(
          source_identifier: "users.csv",
          row_count: 3,
          column_summaries: {"a" => {empty_count: 1}, "b" => {empty_count: 2}}
        )
      end
    end

    context "when column_summaries is empty" do
      let(:column_summaries) { {} }

      it "writes column_summaries as an empty Hash and the other two keys as they were" do
        expect(hash).to eq(source_identifier: "users.csv", row_count: 3, column_summaries: {})
      end
    end
  end
end
