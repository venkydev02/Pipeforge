# frozen_string_literal: true

require_relative "user_project"

# The first run stops after its first chunk, as when the user's process is stopped. The user kept the last
# row number of that chunk and continues from it.
last_row_number = nil
new_engine.run(mode: :run, mapped_columns: mapped_columns, chunk_size: 3) do |chunk_result|
  last_row_number = chunk_result.last_row_number
  break
end

run_result = new_engine.run(mode: :run, mapped_columns: mapped_columns, offset: last_row_number, chunk_size: 3)

puts JSON.generate(totals_of_the_second_run: run_result.to_h, stored_employees: stored_employees)
