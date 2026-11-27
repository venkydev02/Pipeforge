# frozen_string_literal: true

# The whole gem: the core, with the adapter the default settings name.
require "pipeforge"

Dir[File.join(__dir__, "support", "**", "*.rb")].sort.each { |file| require file }

RSpec.configure do |config|
  config.disable_monkey_patching!

  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
    mocks.verify_doubled_constant_names = true
  end

  # Every spec under spec/end_to_end is of type :end_to_end, so the helpers meant for them
  # (config.include ..., type: :end_to_end) reach them without a tag on each file.
  config.define_derived_metadata(file_path: %r{/spec/end_to_end/}) do |metadata|
    metadata[:type] = :end_to_end
  end

  # Run `fit` / `fdescribe` / `focus: true` examples alone while working on one.
  config.filter_run_when_matching :focus

  # Random order shows hidden dependencies between examples. Reproduce a failure with
  # `rspec --seed <number>`.
  config.order = :random
  Kernel.srand config.seed
end
