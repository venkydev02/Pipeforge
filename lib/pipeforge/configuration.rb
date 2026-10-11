# frozen_string_literal: true

require "yaml"

module Pipeforge
  # The engine-wide settings, read once from an engine.yml file. Every part of the engine
  # receives this one object and reads the settings it needs, at the same paths as in the
  # file. A setting the file does not mention keeps its default. Immutable once built.
  #
  # It holds only the settings used so far; the other sections and the validation of values
  # come later.
  #
  # @example
  #   config = Pipeforge::Configuration.new(path: "config/engine.yml")
  #   config.execution.batch_size # => 2000
  class Configuration
    # The +execution+ section: +batch_size+ is how many rows are read and processed at a time.
    ExecutionSettings = Data.define(:batch_size)

    # The +source+ section: +encoding+ is the character encoding of the source file, and
    # +distinct_values_cap+ is the most different values listed per column of the source.
    SourceSettings = Data.define(:encoding, :distinct_values_cap)

    SECTION_NAMES = %w[execution source].freeze

    # @return [String] the path of the file the settings were read from
    attr_reader :path

    # @return [ExecutionSettings]
    attr_reader :execution

    # @return [SourceSettings]
    attr_reader :source

    # @param path [String] path of the engine.yml file
    # @raise [ConfigurationError] the file is missing, is not valid YAML, is not a mapping of
    #   sections and settings, or holds a section or a setting that is not known
    def initialize(path:)
      @path = path
      @sections = read_sections
      reject_unknown_sections
      @execution = build_execution
      @source = build_source
      freeze
    end

    private

    # The sections under `engine:` in the file; empty when the file has none.
    def read_sections
      raise ConfigurationError, "configuration file not found: #{path}" unless File.file?(path)

      document = YAML.safe_load_file(path) || {}
      raise ConfigurationError, "#{path} must hold a mapping at the top level" unless document.is_a?(Hash)

      sections = document["engine"] || {}
      raise ConfigurationError, "engine in #{path} must be a mapping of sections" unless sections.is_a?(Hash)

      sections
    rescue Psych::Exception => e
      raise ConfigurationError, "#{path} is not valid YAML: #{e.message}"
    end

    def reject_unknown_sections
      unknown_sections = @sections.keys.map(&:to_s) - SECTION_NAMES
      raise ConfigurationError, "unknown section #{unknown_sections.join(", ")} in #{path}" if unknown_sections.any?
    end

    def build_execution
      build_section(settings_class: ExecutionSettings, section_name: "execution", defaults: {batch_size: 2000})
    end

    def build_source
      build_section(
        settings_class: SourceSettings,
        section_name: "source",
        defaults: {encoding: "UTF-8", distinct_values_cap: 1000}
      )
    end

    # The section's settings from the file, over the defaults given.
    def build_section(settings_class:, section_name:, defaults:)
      section = @sections[section_name] || {}
      raise ConfigurationError, "section #{section_name} of #{path} must be a mapping of settings" unless section.is_a?(Hash)

      given_settings = section.transform_keys(&:to_sym)
      settings_class.new(**defaults.merge(given_settings))
    rescue ArgumentError => e
      raise ConfigurationError, "unknown setting in section #{section_name} of #{path}: #{e.message}"
    end
  end
end
