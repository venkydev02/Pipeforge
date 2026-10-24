# frozen_string_literal: true

require_relative "lib/pipeforge/version"

Gem::Specification.new do |spec|
  spec.name = "pipeforge" # provisional; see docs/planning/roadmap-and-phases.md open question 9
  spec.version = Pipeforge::VERSION
  spec.authors = ["venky"]
  spec.email = ["developervenkatesh6@gmail.com"]

  spec.summary = "A deterministic relational data migration engine (the core, with no database library)."
  spec.description = "Matches the columns of a CSV source to a target table by name, measures the values, " \
                     "and (later) loads them in batches. The target is reached through an adapter gem, " \
                     "such as pipeforge-activerecord."

  # Version floor = max(feature floor, support floor). Revisit at each Ruby/Rails end-of-life.
  spec.required_ruby_version = ">= 3.3"

  spec.files = Dir["lib/**/*.rb"]
  spec.require_paths = ["lib"]

  spec.add_dependency "smarter_csv", "~> 1.19"

  spec.metadata["rubygems_mfa_required"] = "true"
end
