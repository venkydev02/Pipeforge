# frozen_string_literal: true

require_relative "lib/pipeforge/version"

Gem::Specification.new do |spec|
  spec.name = "pipeforge"
  spec.version = Pipeforge::VERSION
  spec.authors = ["venky"]
  spec.email = ["developervenkatesh6@gmail.com"]

  spec.summary = "A deterministic relational data migration library."
  spec.description = "Matches the columns of a CSV source to a target table by name, measures the values, " \
                     "and loads them through the application's models. ActiveRecord is supported; " \
                     "the application brings the library of its adapter."

  # Version floor = max(feature floor, support floor). Revisit at each Ruby/Rails end-of-life.
  spec.required_ruby_version = ">= 3.3"

  # The core and every adapter. The library of an adapter is not a dependency: the application has it already.
  spec.files = Dir["lib/**/*.rb"]
  spec.require_paths = ["lib"]

  spec.add_dependency "smarter_csv", "~> 1.19"

  spec.metadata["rubygems_mfa_required"] = "true"
end
