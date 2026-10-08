# frozen_string_literal: true

require_relative "lib/pipeforge/version"

Gem::Specification.new do |spec|
  spec.name = "pipeforge" # provisional; see docs/planning/roadmap-and-phases.md open question 9
  spec.version = Pipeforge::VERSION
  spec.authors = ["venky"]
  spec.email = ["developervenkatesh6@gmail.com"]

  spec.summary = "Assisted relational data migration engine for Rails applications."
  spec.description = "Reads a source (CSV) and a target schema through ActiveRecord, recommends a runnable " \
                     "migration plan, then validates, resolves relationships, and loads the data."

  # Version floor = max(feature floor, support floor). Revisit at each Ruby/Rails end-of-life.
  spec.required_ruby_version = ">= 3.3"

  spec.files = Dir["lib/**/*.rb", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord", ">= 8.0", "< 9"
  spec.add_dependency "smarter_csv", "~> 1.19"

  spec.metadata["rubygems_mfa_required"] = "true"
end
