# frozen_string_literal: true

require "yaml"

module Pipeforge
  # The settings of the engine, reached from the module itself: every part of the engine reads
  # the ones it needs here, for example +Pipeforge::Configuration.execution.chunk_size+.
  #
  # {.load} reads them from the conventional file, +config/pipeforge.yml+, relative to the
  # directory the program runs in (the root of a Rails application). It runs once, when the gem
  # is required (see pipeforge.rb), so a file that cannot be used stops the application as it
  # boots. Without that file every setting has its default; a setting the file does not mention
  # keeps its default.
  #
  # Each value is checked when the file is read: a whole number of at least 1 for +chunk_size+
  # and +inclusion_threshold+, and a whole number from 0 to 100 for +reorder_penalty+.
  #
  # A file that cannot be read at all (not valid YAML, not name: value entries) stops at once.
  # Every other mistake is collected, so one ArgumentError lists them all. When {.load} fails,
  # the settings it had before stay.
  #
  # @example
  #   Pipeforge::Configuration.execution.chunk_size  # => 2000
  module Configuration
    # Where the engine looks for its settings, by convention.
    DEFAULT_PATH = "config/pipeforge.yml"

    # The +execution+ section: +chunk_size+ is how many rows are read and processed at a time.
    ExecutionSettings = Data.define(:chunk_size)

    # The +recommendation+ section: +inclusion_threshold+ is the lowest score (a whole number of
    # at least 1) a pair of columns needs to be a match, and +reorder_penalty+ is how many points
    # (0 to 100) are taken off when the matched words are in a different order.
    RecommendationSettings = Data.define(:inclusion_threshold, :reorder_penalty)

    # The sections the settings file may have.
    SECTION_NAMES = %w[execution recommendation].freeze

    # The value of each setting when the file does not give it.
    DEFAULTS = {
      execution: {chunk_size: 2000},
      recommendation: {inclusion_threshold: 55, reorder_penalty: 10}
    }.freeze

    class << self
      # @return [ExecutionSettings]
      attr_reader :execution

      # @return [RecommendationSettings]
      attr_reader :recommendation

      # Reads {DEFAULT_PATH} and keeps its settings, replacing the ones kept before.
      #
      # @raise [ArgumentError] the file is not valid YAML or is not made of name: value
      #   entries (stops at once); or it holds errors in its sections and settings (an unknown
      #   section or setting, a section that is not settings, a value of the wrong type or
      #   range), all listed in the message
      def load
        @error_messages = []
        @sections_by_name = read_sections
        execution_settings = build_execution
        recommendation_settings = build_recommendation
        raise_errors

        @execution = execution_settings
        @recommendation = recommendation_settings
      end

      private

      # The sections under +engine:+ in the file; empty when the file has none, or when there is
      # no file (every setting then has its default). A section the engine does not know is
      # recorded as an error, and the rest is still read.
      def read_sections
        return {} unless File.file?(DEFAULT_PATH)

        document = YAML.safe_load_file(DEFAULT_PATH) || {}
        unless document.is_a?(Hash)
          fail_fast(message: ArgumentMessages::MESSAGES.fetch(:settings_not_name_value_entries).call)
        end

        sections = document["engine"] || {}
        unless sections.is_a?(Hash)
          fail_fast(message: ArgumentMessages::MESSAGES.fetch(:settings_engine_not_sections).call)
        end

        (sections.keys.map(&:to_s) - SECTION_NAMES).each do |section_name|
          add_error(message: ArgumentMessages::MESSAGES.fetch(:settings_section_unknown).call(section_name: section_name))
        end

        sections
      rescue Psych::Exception => yaml_error
        fail_fast(message: ArgumentMessages::MESSAGES.fetch(:settings_not_valid_yaml).call(reason: yaml_error.message))
      end

      # Records a mistake as a sentence.
      def add_error(message:)
        @error_messages << message
      end

      # Records the mistake and raises at once: nothing after it can be checked.
      def fail_fast(message:)
        add_error(message: message)
        raise_errors
      end

      def build_execution
        execution_settings = build_section(
          settings_class: ExecutionSettings, section_name: "execution", defaults: DEFAULTS.fetch(:execution)
        )
        require_positive_whole_number(setting_name: "execution.chunk_size", value: execution_settings.chunk_size)

        execution_settings
      end

      def build_recommendation
        recommendation_settings = build_section(
          settings_class: RecommendationSettings,
          section_name: "recommendation",
          defaults: DEFAULTS.fetch(:recommendation)
        )
        require_positive_whole_number(
          setting_name: "recommendation.inclusion_threshold", value: recommendation_settings.inclusion_threshold
        )
        require_whole_number_from_0_to_100(
          setting_name: "recommendation.reorder_penalty", value: recommendation_settings.reorder_penalty
        )

        recommendation_settings
      end

      # The section's settings from the file, over the defaults given. A section that is not
      # settings, or a setting that is not known, is recorded as an error and the rest is still
      # read, so the values that can be checked are checked.
      def build_section(settings_class:, section_name:, defaults:)
        section = @sections_by_name[section_name] || {}

        unless section.is_a?(Hash)
          add_error(message: ArgumentMessages::MESSAGES.fetch(:settings_section_not_settings).call(section_name: section_name))
          return settings_class.new(**defaults)
        end

        given_settings = section.transform_keys(&:to_sym)

        (given_settings.keys - settings_class.members).each do |setting_name|
          add_error(
            message: ArgumentMessages::MESSAGES.fetch(:settings_setting_unknown).call(
              setting_name: setting_name, section_name: section_name
            )
          )
        end

        settings_class.new(**defaults.merge(given_settings.slice(*settings_class.members)))
      end

      # A whole number (not a decimal, text, true or nothing) of at least 1.
      def require_positive_whole_number(setting_name:, value:)
        return if Utilities.positive_whole_number?(value: value)

        add_error(
          message: ArgumentMessages::MESSAGES.fetch(:value_not_whole_number_at_least_1).call(name: setting_name, value: value)
        )
      end

      # A whole number from 0 to 100, for a score or a number of points.
      def require_whole_number_from_0_to_100(setting_name:, value:)
        return if value.is_a?(Integer) && value.between?(0, 100)

        add_error(
          message: ArgumentMessages::MESSAGES.fetch(:value_not_whole_number_from_0_to_100).call(name: setting_name, value: value)
        )
      end

      # One ArgumentError for everything collected: the sentence itself for one, a list for several.
      def raise_errors
        return if @error_messages.empty?

        raise ArgumentError, ArgumentMessages::MESSAGES.fetch(:settings_file_has_errors).call(
          path: DEFAULT_PATH, error_messages: @error_messages
        )
      end
    end
  end
end
