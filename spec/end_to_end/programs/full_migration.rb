# frozen_string_literal: true

require_relative "user_project"

engine = new_engine
header_analysis = engine.analyze_headers

# The user starts from the matches and adds the columns whose names were too different to match.
reviewed_columns = {}
header_analysis.matches.each do |match|
  reviewed_columns[match[:target_column_name]] = {source_column_name: match[:source_column_name]}
end
reviewed_columns["joined_on"] = {source_column_name: "Date of Joining"}

# First look at the values as they are, to learn what needs a mapping.
analysis_before_mapping = engine.analyze_column_values(mapped_columns: reviewed_columns)

reviewed_columns["status"] = reviewed_columns["status"].merge(value_mapping: STATUS_MAPPING)
reviewed_columns["salary"] = reviewed_columns["salary"].merge(value_mapping: SALARY_MAPPING)
analysis_after_mapping = engine.analyze_column_values(mapped_columns: reviewed_columns)
employees_after_the_analyses = stored_employees

def run_report(engine:, mode:, mapped_columns:)
  chunk_results = []
  run_result = engine.run(mode: mode, mapped_columns: mapped_columns) { |chunk_result| chunk_results << chunk_result.to_h }

  {totals: run_result.to_h, chunk_results: chunk_results, stored_employees: stored_employees}
end

dry_run = run_report(engine: engine, mode: :dry_run, mapped_columns: reviewed_columns)
real_run = run_report(engine: engine, mode: :run, mapped_columns: reviewed_columns)

puts JSON.generate(
  header_analysis: header_analysis.to_h,
  analysis_before_mapping: analysis_before_mapping.to_h,
  analysis_after_mapping: analysis_after_mapping.to_h,
  employees_after_the_analyses: employees_after_the_analyses,
  dry_run: dry_run,
  run: real_run
)
