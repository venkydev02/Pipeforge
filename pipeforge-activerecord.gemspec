# frozen_string_literal: true

require_relative "lib/pipeforge/version"

Gem::Specification.new do |spec|
  spec.name = "pipeforge-activerecord"
  spec.version = Pipeforge::VERSION # the version of the core it carries
  spec.authors = ["venky"]
  spec.email = ["developervenkatesh6@gmail.com"]

  spec.summary = "A deterministic relational data migration engine, for ActiveRecord."
  spec.description = "Matches the columns of a CSV source to a target table by name, measures the values, " \
                     "and loads them through the application's ActiveRecord models. " \
                     "The engine itself (the core) comes inside this gem."

  # Version floor = max(feature floor, support floor). Revisit at each Ruby/Rails end-of-life.
  spec.required_ruby_version = ">= 3.3"

  # The gem of an adapter carries the core and that adapter's own folder and entry file, which all sit in lib,
  # and no other adapter. A gemspec can list only files below its own folder, which is why it sits at the root.
  adapter = "activerecord"
  other_adapter_files = Dir["lib/pipeforge/adapters/*/**/*.rb"] - Dir["lib/pipeforge/adapters/#{adapter}/**/*.rb"]
  other_entry_files = Dir["lib/pipeforge-*.rb"] - ["lib/pipeforge-#{adapter}.rb"]
  spec.files = Dir["lib/**/*.rb"] - other_adapter_files - other_entry_files
  spec.require_paths = ["lib"]

  spec.add_dependency "smarter_csv", "~> 1.19"
  spec.add_dependency "activerecord", ">= 8.0", "< 9"

  spec.metadata["rubygems_mfa_required"] = "true"
end
