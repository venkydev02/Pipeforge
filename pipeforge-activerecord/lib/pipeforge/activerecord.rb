# frozen_string_literal: true

# The entry file of the pipeforge-activerecord gem (a dash in a gem name is a slash in its path).
# It loads the gem's own files, then the core and ActiveRecord, and installs the adapter in the
# core's TargetAdapter, so the engine uses it without being told.
require_relative "activerecord/version"
require_relative "activerecord/adapter"
require "pipeforge"
require "active_record"

Pipeforge::TargetAdapter.install(adapter: Pipeforge::ActiveRecordAdapter.new)
