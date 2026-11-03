# frozen_string_literal: true

# The entry file of the pipeforge-activerecord gem, and the only file a consumer requires: Bundler
# requires it for a gem of this name. It loads the core (which comes in the same gem) and ActiveRecord,
# then the adapter's own files, and installs the adapter in the core's TargetAdapter, so the engine uses
# it without being told.
require "pipeforge"
require "active_record"
require_relative "pipeforge/adapters/activerecord/adapter"

Pipeforge::TargetAdapter.install(adapter: Pipeforge::ActiveRecordAdapter.new)
