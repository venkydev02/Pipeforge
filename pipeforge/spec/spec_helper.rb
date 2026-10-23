# frozen_string_literal: true

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

  # Run `fit` / `fdescribe` / `focus: true` examples alone while working on one.
  config.filter_run_when_matching :focus

  # Random order shows hidden dependencies between examples. Reproduce a failure with
  # `rspec --seed <number>`.
  config.order = :random
  Kernel.srand config.seed
end
