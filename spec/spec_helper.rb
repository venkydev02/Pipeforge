# frozen_string_literal: true

# The whole gem: the core and the ActiveRecord adapter, which installs itself.
require "pipeforge-activerecord"

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

  # Every spec under spec/integration is of type :integration, so the helpers meant for them
  # (config.include ..., type: :integration) reach them without a tag on each file.
  config.define_derived_metadata(file_path: %r{/spec/integration/}) do |metadata|
    metadata[:type] = :integration
  end

  # Run `fit` / `fdescribe` / `focus: true` examples alone while working on one.
  config.filter_run_when_matching :focus

  # Random order shows hidden dependencies between examples. Reproduce a failure with
  # `rspec --seed <number>`.
  config.order = :random
  Kernel.srand config.seed
end
