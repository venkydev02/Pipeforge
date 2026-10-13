# frozen_string_literal: true

require_relative "value_analyzer"

module Pipeforge
  # The entry point of the engine. It is given the configuration file and the source file once,
  # checks them, and hands the work to the stages, so the caller does not repeat the paths for
  # each action.
  #
  # @example
  #   engine = Pipeforge::Engine.new(config_path: "config/engine.yml", source_path: "data/users.csv")
  #   result = engine.analyze_values(
  #     mapped_columns: {"Mail" => {target_column: "email", type: "string"}}
  #   )
  class Engine
    # @return [Configuration] the settings read from the configuration file
    attr_reader :config

    # @return [String] the path of the source file
    attr_reader :source_path

    # Both paths are always given explicitly; they are never searched for.
    #
    # @param config_path [String] path of the engine.yml file
    # @param source_path [String] path of the CSV file
    # @raise [ConfigurationError] the configuration file cannot be used
    # @raise [Source::MissingSourceError] the source is not a readable file
    def initialize(config_path:, source_path:)
      @config_path = config_path
      @source_path = source_path
      @config = build_config
      ensure_readable_source
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
    # @raise [KeyError] a column has no +target_column+ or no +type+
    # @raise [Source::MissingColumnError] a mapped source column is not in the file
    # @raise [Source::MalformedSourceError] a row cannot be parsed
    def analyze_values(mapped_columns:)
      ValueAnalyzer.new(config: @config).call(path: @source_path, mapped_columns: mapped_columns)
    end

    private

    def build_config
      Configuration.new(path: @config_path)
    end

    def ensure_readable_source
      return if File.file?(@source_path) && File.readable?(@source_path)

      raise Source::MissingSourceError.single(
        code: :source_not_readable,
        message: "source file not found or not readable: #{@source_path}",
        path: @source_path
      )
    end
  end
end
