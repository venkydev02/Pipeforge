# frozen_string_literal: true

module Pipeforge
  # The core's one door to the target. The core calls the methods of this module, and
  # each call goes to the adapter that an adapter gem installed when it was loaded. The core
  # never holds, creates or receives an adapter.
  #
  # The installed adapter is shared by every engine, so it must keep no state of its own.
  # If two adapter gems are loaded, the last one installed is used.
  #
  # @example the adapter gem installs its adapter once, when it is loaded
  #   Pipeforge::TargetAdapter.install(adapter: Pipeforge::ActiveRecordAdapter.new)
  #
  # @example the core reads the target through the module
  #   Pipeforge::TargetAdapter.schema(target_model: "User")
  module TargetAdapter
    class << self
      # @param adapter [#schema, nil] the object that does the work, following the adapter
      #   contract; nil means no adapter is installed
      def install(adapter:)
        @adapter = adapter
      end

      # Checks that an adapter is installed. The engine calls it when it is created.
      #
      # @raise [TargetAdapterError] no adapter is installed (+target_adapter_not_installed+)
      def ensure_installed
        return unless @adapter.nil?

        raise TargetAdapterError.single(
          code: :target_adapter_not_installed,
          message: "no target adapter is installed; add an adapter gem such as pipeforge-activerecord"
        )
      end

      # The structure of the target table of a model.
      #
      # @param target_model [String] the name of the model
      # @return [TargetSchema]
      # @raise [TargetAdapterError] no adapter is installed (+target_adapter_not_installed+)
      # @raise [TargetSchemaError] the model or its table cannot be found
      def schema(target_model:)
        ensure_installed
        @adapter.schema(target_model: target_model)
      end

      # The adapter's object for one target model. The run asks for it once and uses it for every
      # record: +build_record(attributes:)+ returns the adapter's wrapper of one record (see
      # {RunProcessor::RowCandidate#model_record}), +preload_parents(records:)+ loads the parents a chunk
      # needs, and +cast_value(column_name:, value:)+ says whether the adapter can cast a value (a
      # text, or what a value mapping gives, as it is) in a column and what the model would load, in Ruby and in JSON
      # types: a +CastResult+ (+castable+, +cast_value+, +json_value+), with the two values nil when the value cannot
      # be cast. +transaction(rollback_at_end:)+ runs a block inside one transaction of the target database, rolled
      # back when the block ends if +rollback_at_end+ is true. What +build_record+ returns also answers +load+, which
      # writes the record.
      #
      # @param target_model [String] the name of the model
      # @return [#build_record, #preload_parents, #cast_value, #transaction] the model adapter
      # @raise [TargetAdapterError] no adapter is installed (+target_adapter_not_installed+)
      # @raise [TargetSchemaError] the model or its table cannot be found
      def model_adapter(target_model:)
        ensure_installed
        @adapter.model_adapter(target_model: target_model)
      end
    end
  end
end
