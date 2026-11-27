# frozen_string_literal: true

# The story of the programs: see spec/end_to_end/programs/user_project.rb.
RSpec.describe "A user's program moving employees from an old HR export" do
  context "when pipeforge.yml sets execution.chunk_size to 3 and run gets no chunk_size" do
    before(:context) do
      @report = run_consumer_program(
        program_name: "chunked_dry_run", files: {"config/pipeforge.yml" => "engine:\n  execution:\n    chunk_size: 3\n"}
      ).report
    end

    it "gives the block chunks of 3 rows" do
      expect(@report.fetch("row_number_ranges")).to eq([[1, 3], [4, 6], [7, 9]])
    end
  end

  context "when the user reviews the matches, maps the old values, does a dry run and then a run" do
    before(:context) { @report = run_consumer_program(program_name: "full_migration").report }

    let(:header_analysis) { @report.fetch("header_analysis") }
    let(:analysis_before_mapping) { @report.fetch("analysis_before_mapping") }
    let(:analysis_after_mapping) { @report.fetch("analysis_after_mapping") }
    let(:dry_run) { @report.fetch("dry_run") }
    let(:real_run) { @report.fetch("run") }
    let(:failed_rows) { real_run.fetch("chunk_results").flat_map { |chunk_result| chunk_result.fetch("failed_rows") } }

    def summary_of(analysis:, target_column_name:)
      analysis.fetch("column_summaries").fetch(target_column_name)
    end

    def incompatible_values_of(analysis:, target_column_name:)
      summary = summary_of(analysis: analysis, target_column_name: target_column_name)

      summary.fetch("distinct_values").fetch("incompatible").map { |listed| listed.fetch("value") }
    end

    def codes_by_row_number(failed_rows:)
      codes = {}
      failed_rows.each do |failed_row|
        codes[failed_row.fetch("row_number")] = failed_row.fetch("errors").map { |error| error.fetch("code") }
      end

      codes
    end

    describe "finding which column of the export goes where" do
      it "suggests the columns whose names are close" do
        matched_names = header_analysis.fetch("matches").map { |match| match.values_at("target_column_name", "source_column_name") }

        expect(matched_names).to eq(
          [["email", "Email"], ["full_name", "Full Name"], ["status", "Status"], ["salary", "Salary"], ["department_id", "Department Id"]]
        )
      end

      it "lists the columns of the export it could not place" do
        expect(header_analysis.fetch("unmatched_source_column_names")).to eq(["Date of Joining", "Remarks"])
      end

      it "lists the columns of the table that nothing fills" do
        unfilled = header_analysis.fetch("unmatched_target_columns").map { |entry| entry.fetch("target_column_name") }

        expect(unfilled).to eq(["joined_on", "phone"])
      end
    end

    describe "learning which values need a mapping" do
      it "lists every status of the old system as one the application does not accept" do
        expect(incompatible_values_of(analysis: analysis_before_mapping, target_column_name: "status"))
          .to contain_exactly("Working", "On Leave", "Left", "Contractor")
      end

      # The model reads a text it does not know as a number as 0, so casted_to is what warns the user.
      it "shows with casted_to that an unmapped N/A salary would be stored as 0.0" do
        compatible = summary_of(analysis: analysis_before_mapping, target_column_name: "salary").fetch("distinct_values").fetch("compatible")

        expect(compatible.find { |listed| listed.fetch("value") == "N/A" }).to include("casted_to" => "0.0")
      end

      it "leaves only the status the user did not map" do
        expect(incompatible_values_of(analysis: analysis_after_mapping, target_column_name: "status")).to eq(["Contractor"])
      end

      it "counts the mapped N/A of the salaries as empty" do
        expect(summary_of(analysis: analysis_after_mapping, target_column_name: "salary").fetch("empty")).to eq(1)
      end

      it "points at the joining date that is not in the calendar" do
        expect(incompatible_values_of(analysis: analysis_after_mapping, target_column_name: "joined_on")).to eq(["2023-02-30"])
      end

      it "stores no employee" do
        expect(@report.fetch("employees_after_the_analyses")).to eq([])
      end
    end

    describe "what is stored" do
      it "stores no employee in the dry run" do
        expect(dry_run.fetch("stored_employees")).to eq([])
      end

      it "stores the correct rows in the run, with the application's statuses and an empty salary for N/A" do
        expect(real_run.fetch("stored_employees")).to eq(
          [
            ["priya@example.com", "active", "85000.0", "2021-04-12", "Engineering"],
            ["arjun@example.com", "on_leave", nil, "2022-01-03", "Engineering"],
            ["meena@example.com", "inactive", "72000.0", "2019-07-22", "Engineering"]
          ]
        )
      end
    end

    describe "knowing what to fix" do
      it "counts the processed, stored and failed rows" do
        expect(real_run.fetch("totals")).to eq("processed_rows_count" => 9, "valid_rows_count" => 3, "failed_rows_count" => 6)
      end

      it "gives each failed row its row number in the export and the reason" do
        expect(codes_by_row_number(failed_rows: failed_rows)).to eq(
          2 => ["value_out_of_range"], 4 => ["value_not_accepted"], 5 => ["parent_missing"], 7 => ["value_not_unique"],
          8 => ["value_missing"], 9 => ["value_not_accepted"]
        )
      end

      it "reports in the dry run the same rows and reasons, before anything is stored" do
        dry_run_failed_rows = dry_run.fetch("chunk_results").flat_map { |chunk_result| chunk_result.fetch("failed_rows") }

        expect(codes_by_row_number(failed_rows: dry_run_failed_rows)).to eq(codes_by_row_number(failed_rows: failed_rows))
      end
    end

    describe "the results as JSON, for the user to show or keep" do
      let(:status_summary) { summary_of(analysis: analysis_after_mapping, target_column_name: "status") }
      let(:distinct_values) { status_summary.fetch("distinct_values") }
      let(:chunk_result) { real_run.fetch("chunk_results").first }

      it "has the keys of the header result" do
        expect(header_analysis.keys).to contain_exactly(
          "target_table_name", "model_name", "matches", "unmatched_source_column_names", "unmatched_target_columns"
        )
      end

      it "has the keys of a match" do
        expect(header_analysis.fetch("matches").first.keys).to contain_exactly(
          "target_column_name", "source_column_name", "score", "tied_source_column_names", "metadata"
        )
      end

      it "has the keys of an unmatched target column" do
        expect(header_analysis.fetch("unmatched_target_columns").first.keys).to contain_exactly("target_column_name", "metadata")
      end

      it "has the keys of the value result" do
        expect(analysis_after_mapping.keys).to contain_exactly("row_count", "column_summaries")
      end

      it "has the keys of a column summary" do
        expect(status_summary.keys).to contain_exactly("source_column_name", "position", "empty", "distinct_values", "value_mapping")
      end

      it "has the keys of distinct_values" do
        expect(distinct_values.keys).to contain_exactly("compatible", "incompatible", "compatible_count", "incompatible_count")
      end

      it "shows an old status with the status it is loaded as" do
        working = distinct_values.fetch("compatible").find { |listed| listed.fetch("value") == "Working" }

        expect(working).to include("mapping_applied" => true, "mapped_value" => "active", "casted_to" => "active")
      end

      it "has the keys of a compatible value" do
        expect(distinct_values.fetch("compatible").first.keys).to contain_exactly(
          "value", "count", "mapping_applied", "mapped_value", "casted_to"
        )
      end

      it "has the keys of an incompatible value" do
        expect(distinct_values.fetch("incompatible").first.keys).to contain_exactly(
          "value", "count", "mapping_applied", "mapped_value", "casted_to", "reason"
        )
      end

      it "has the keys of a chunk result" do
        expect(chunk_result.keys).to contain_exactly(
          "first_row_number", "last_row_number", "processed_rows_count", "valid_rows_count", "failed_rows_count", "failed_rows"
        )
      end

      it "has the keys of a failed row" do
        expect(failed_rows.first.keys).to contain_exactly("row_number", "attributes", "errors")
      end

      it "has the keys of an error" do
        expect(failed_rows.first.fetch("errors").first.keys).to contain_exactly(
          "origin", "code", "kind", "target_column_name", "message", "details", "value"
        )
      end
    end
  end

  context "when a run is stopped after its first chunk and the user continues with offset" do
    before(:context) { @report = run_consumer_program(program_name: "resumed_run").report }

    # The model refuses a repeated email, so the table alone looks right even when no row is skipped.
    it "processes only the 6 rows after the first chunk" do
      expect(@report.fetch("totals_of_the_second_run").fetch("processed_rows_count")).to eq(6)
    end

    it "stores each correct employee once" do
      expect(@report.fetch("stored_employees").map(&:first)).to eq(["priya@example.com", "arjun@example.com", "meena@example.com"])
    end
  end
end
