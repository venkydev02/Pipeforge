# frozen_string_literal: true

# Pipeforge, a relational data migration library: one gem with the core and its adapters. The core names no
# database library: the target is reached through an adapter, which is loaded here, when the gem is required.
# See docs/architecture/overview.md.
require_relative "pipeforge/version"
require_relative "pipeforge/errors"
require_relative "pipeforge/error_catalog"
require_relative "pipeforge/utilities"
require_relative "pipeforge/cast_result"
require_relative "pipeforge/resolved_mapped_column"
require_relative "pipeforge/adapter_registry"
require_relative "pipeforge/configuration"
require_relative "pipeforge/engine"

# Read the settings once, now that the gem is loaded; a file that cannot be used stops here.
Pipeforge::Configuration.load

# The adapter is the one the settings name. A library it needs that is missing stops here.
Pipeforge::Engine.install_target(
  target_class: Pipeforge::AdapterRegistry.resolve(name: Pipeforge::Configuration.target.adapter)
)
