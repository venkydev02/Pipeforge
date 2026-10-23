# frozen_string_literal: true

# The core of the relational data migration engine. It has no database library: the target is
# reached through an adapter gem, such as pipeforge-activerecord, which registers itself when
# it is loaded. See docs/architecture/overview.md.
require_relative "pipeforge/version"
require_relative "pipeforge/errors"
require_relative "pipeforge/utilities"
require_relative "pipeforge/configuration"
require_relative "pipeforge/engine"

# Read the settings once, now that the gem is loaded; a file that cannot be used stops here.
Pipeforge::Configuration.load
