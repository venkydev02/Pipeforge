# frozen_string_literal: true

require_relative "lib/pipeforge/activerecord/version"

Gem::Specification.new do |spec|
  spec.name = "pipeforge-activerecord"
  spec.version = Pipeforge::ActiveRecordAdapter::VERSION
  spec.authors = ["venky"]
  spec.email = ["developervenkatesh6@gmail.com"]

  spec.summary = "The ActiveRecord adapter for Pipeforge."
  spec.description = "Reads the structure of a target table and its ActiveRecord model for Pipeforge. " \
                     "Install this gem; the pipeforge core comes with it."

  spec.required_ruby_version = ">= 3.3"

  spec.files = Dir["lib/**/*.rb"]
  spec.require_paths = ["lib"]

  # The versions of the core whose adapter contract this adapter follows. Widen the range when a
  # new core release keeps the contract; narrow it when the contract breaks.
  spec.add_dependency "pipeforge", ">= 0.0.0", "< 0.1"
  spec.add_dependency "activerecord", ">= 8.0", "< 9"

  spec.metadata["rubygems_mfa_required"] = "true"
end
