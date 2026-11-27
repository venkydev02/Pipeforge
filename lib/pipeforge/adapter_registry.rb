# frozen_string_literal: true

module Pipeforge
  # The adapters the gem knows: for each name, the class of its target and the file that holds it.
  # Resolving a name requires that file and gives the class.
  #
  # @api private
  module AdapterRegistry
    ADAPTERS = {
      "activerecord" => {class_name: "Pipeforge::ActiveRecordTarget", path: "pipeforge/adapters/activerecord/adapter"}
    }.freeze

    class << self
      # @return [Array<String>] the names of the adapters
      def names
        ADAPTERS.keys
      end

      # Requires the file of an adapter and gives its target class.
      #
      # @param name [String] one of {names}
      # @return [Class]
      # @raise [LoadError] the file of the adapter, or a library it needs, cannot be loaded
      def resolve(name:)
        adapter = ADAPTERS.fetch(name)

        begin
          require adapter.fetch(:path)
        rescue LoadError => load_error
          raise LoadError, ArgumentMessages::MESSAGES.fetch(:adapter_not_loaded).call(name: name, reason: load_error.message)
        end

        Object.const_get(adapter.fetch(:class_name))
      end
    end
  end
end
