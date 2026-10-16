# frozen_string_literal: true

require_relative "value_analyzer"

module Pipeforge
  # The entry point of the engine. It is given the configuration file and the source file once,
  # checks them, and hands the work to the stages, so the caller does not repeat the paths for
  # each action.
  #
  # @example
  #   engine = Pipeforge::Engine.new(config_path: "config/engine.yml", source_io: File.open("data/users.csv"))
  #   result = engine.analyze_values(
  #     mapped_columns: {"Mail" => {target_column: "email", type: "string"}}
  #   )
  class Engine
    # The methods the source must have, and the error code for each one that is missing.
    SOURCE_IO_METHODS = {
      read: :source_io_missing_read,
      rewind: :source_io_missing_rewind,
      seek: :source_io_missing_seek
    }.freeze

    # What a mapped column must carry, and the error code for each piece that is missing.
    MISSING_PIECE_CODES = {
      target_column: :column_missing_target_column,
      type: :column_missing_type
    }.freeze

    # @return [Configuration] the settings read from the configuration file
    attr_reader :config

    # @return [IO] the source: any object with +read+, +rewind+ and +seek+ (ADR-17 item 12)
    attr_reader :source_io

    # The configuration path is always given explicitly; it is never searched for.
    #
    # @param config_path [String] path of the engine.yml file
    # @param source_io [IO] the CSV source, for example +File.open("data/users.csv")+. It is
    #   rewound before each read, so the same object can be used again.
    # @raise [ConfigurationError] the configuration file cannot be used
    # @raise [Source::UnsupportedSourceError] the source is missing a method the engine needs
    def initialize(config_path:, source_io:)
      @config_path = config_path
      @source_io = source_io
      @config = build_config
      ensure_source_methods
    end

    # Measures the mapped columns of the source file: how many values are empty, how many fit
    # the type of the target column, and which distinct values do and do not fit.
    #
    # Call it again after editing the +value_mapping+ of a column in the result to see the facts
    # again: with a value mapping, each value is measured as the value it maps to, so the counts
    # show what would be loaded, and the mapping comes back in the result to be edited once
    # more. The file is read again each time, so a changed file or mapping is picked up as well.
    #
    # @param mapped_columns [Hash{String => Hash}] source column => {target_column:, type:, ...,
    #   value_mapping: {value in the file => value to load}}. +value_mapping+ is optional, and a
    #   value that maps to nil or a blank is loaded as empty. The type keys are described in
    #   {ValueAnalyzer::TypeChecker}.
    # @return [ValueAnalyzer::Result]
    # @raise [IncompleteColumnsError] a column has no +target_column+ or no +type+; every such
    #   column is listed
    # @raise [Source::MissingColumnError] a mapped source column is not in the file
    # @raise [Source::MalformedSourceError] a row cannot be parsed
    def analyze_values(mapped_columns:)
      reject_incomplete_columns(mapped_columns: mapped_columns)

      ValueAnalyzer.new(config: @config, source_io: @source_io, mapped_columns: mapped_columns).call
    end

    private

    # Raises IncompleteColumnsError, listing every piece a mapped column is missing.
    def reject_incomplete_columns(mapped_columns:)
      errors = []

      mapped_columns.each do |source_column, column_info|
        MISSING_PIECE_CODES.each do |piece, code|
          next if column_info.key?(piece)

          errors << {
            code: code,
            message: "#{source_column} has no #{piece}",
            source_column: source_column
          }
        end
      end

      return if errors.empty?

      raise IncompleteColumnsError.new(
        message: "mapped columns are incomplete: #{errors.map { |error| error[:message] }.join(", ")}",
        errors: errors
      )
    end

    def build_config
      Configuration.new(path: @config_path)
    end

    # Raises Source::UnsupportedSourceError, listing every method the source does not have.
    def ensure_source_methods
      errors = []

      SOURCE_IO_METHODS.each do |method_name, code|
        next if @source_io.respond_to?(method_name)

        errors << {
          code: code,
          message: "source does not respond to #{method_name}",
          method: method_name
        }
      end

      return if errors.empty?

      raise Source::UnsupportedSourceError.new(
        message: "source is missing: #{errors.map { |error| error[:method] }.join(", ")}",
        errors: errors
      )
    end
  end
end
