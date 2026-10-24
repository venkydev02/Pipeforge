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
  #   Pipeforge::TargetAdapter.schema(target_table: "users")
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

      # The structure of the target table.
      #
      # @param target_table [String]
      # @return [TargetSchema]
      # @raise [TargetAdapterError] no adapter is installed (+target_adapter_not_installed+)
      def schema(target_table:)
        ensure_installed
        @adapter.schema(target_table: target_table)
      end
    end
  end
end
