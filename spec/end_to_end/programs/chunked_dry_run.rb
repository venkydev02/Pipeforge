# frozen_string_literal: true

require_relative "user_project"

row_number_ranges = []
new_engine.run(mode: :dry_run, mapped_columns: mapped_columns) do |chunk_result|
  row_number_ranges << [chunk_result.first_row_number, chunk_result.last_row_number]
end

puts JSON.generate(row_number_ranges: row_number_ranges)
