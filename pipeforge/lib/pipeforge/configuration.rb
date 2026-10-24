# frozen_string_literal: true

require "yaml"

module Pipeforge
  # The settings of the engine, reached from the module itself: every part of the engine reads
  # the ones it needs here, for example +Pipeforge::Configuration.source.distinct_values_cap+.
  #
  # {.load} reads them from the conventional file, +config/pipeforge.yml+, relative to the
  # directory the program runs in (the root of a Rails application). It runs once, when the gem
  # is required (see pipeforge.rb), so a file that cannot be used stops the application as it
  # boots. Without that file every setting has its default; a setting the file does not mention
  # keeps its default.
  #
  # Each value is checked when the file is read: a whole number of at least 1 for +batch_size+,
  # +distinct_values_cap+ and +inclusion_threshold+, a whole number from 0 to 100 for
  # +reorder_penalty+, true or false for +fingerprint+.
  #
  # A file that cannot be read at all (not valid YAML, not name: value entries) stops at once.
  # Every other error is collected, so one ConfigurationError lists them all, each with its own
  # code (see {ConfigurationError}). When {.load} fails, the settings it had before stay.
  #
  # @example
  #   Pipeforge::Configuration.execution.batch_size  # => 2000
  module Configuration
    # Where the engine looks for its settings, by convention.
    DEFAULT_PATH = "config/pipeforge.yml"

    # The +execution+ section: +batch_size+ is how many rows are read and processed at a time.
    ExecutionSettings = Data.define(:batch_size)

    # The +source+ section: +distinct_values_cap+ is the most different values listed per column of
    # the source, and +fingerprint+ turns on the fingerprint of the source rows (true or false).
    SourceSettings = Data.define(:distinct_values_cap, :fingerprint)

    # The +recommendation+ section: +inclusion_threshold+ is the lowest score (a whole number of
    # at least 1) a pair of columns needs to be a match, and +reorder_penalty+ is how many points
    # (0 to 100) are taken off when the matched words are in a different order.
    RecommendationSettings = Data.define(:inclusion_threshold, :reorder_penalty)

    SECTION_NAMES = %w[execution source recommendation].freeze

    class << self
      # @return [String] the path the settings were read from
      attr_reader :path

      # @return [ExecutionSettings]
      attr_reader :execution

      # @return [SourceSettings]
      attr_reader :source

      # @return [RecommendationSettings]
      attr_reader :recommendation

      # Reads {DEFAULT_PATH} and keeps its settings, replacing the ones kept before.
      #
      # @raise [ConfigurationError] the file is not valid YAML or is not made of name: value
      #   entries (stops at once); or it holds errors in its sections and settings (an unknown
      #   section or setting, a section that is not settings, a value of the wrong type or
      #   range), all listed in one error
      def load
        @errors = []
        @sections = read_sections
        execution = build_execution
        source = build_source
        recommendation = build_recommendation
        raise_errors

        @path = DEFAULT_PATH
        @execution = execution
        @source = source
        @recommendation = recommendation
      end

      private

      # The sections under `engine:` in the file; empty when the file has none, or when there is
      # no file (every setting then has its default). A section the engine does not know is
      # recorded as an error, and the rest is still read.
      def read_sections
        return {} unless File.file?(DEFAULT_PATH)

        document = YAML.safe_load_file(DEFAULT_PATH) || {}
        unless document.is_a?(Hash)
          fail_fast(
            code: :config_file_not_name_value_entries,
            message: "must be made of name: value entries at the top level"
          )
        end

        sections = document["engine"] || {}
        unless sections.is_a?(Hash)
          fail_fast(
            code: :engine_not_sections,
            message: "engine must hold sections, each written as a name with entries under it"
          )
        end

        (sections.keys.map(&:to_s) - SECTION_NAMES).each do |section_name|
          add_error(code: :unknown_section, message: "unknown section #{section_name}", section: section_name)
        end

        sections
      rescue Psych::Exception => e
        fail_fast(code: :config_file_not_valid_yaml, message: "not valid YAML: #{e.message}")
      end

      # Records an error: its code, its sentence, and the fields that say where it is.
      def add_error(code:, message:, **context)
        @errors << {code: code, message: message, **context}
      end

      # Records the error and raises at once, through the one place that raises: nothing after
      # this can be checked.
      def fail_fast(code:, message:)
        add_error(code: code, message: message)
        raise_errors
      end

      def build_execution
        execution = build_section(
          settings_class: ExecutionSettings, section_name: "execution", defaults: {batch_size: 2000}
        )
        require_positive_whole_number(setting_name: "execution.batch_size", value: execution.batch_size)

        execution
      end

      def build_source
        source = build_section(
          settings_class: SourceSettings,
          section_name: "source",
          defaults: {distinct_values_cap: 1000, fingerprint: false}
        )
        require_positive_whole_number(setting_name: "source.distinct_values_cap", value: source.distinct_values_cap)
        require_true_or_false(setting_name: "source.fingerprint", value: source.fingerprint)

        source
      end

      def build_recommendation
        recommendation = build_section(
          settings_class: RecommendationSettings,
          section_name: "recommendation",
          defaults: {inclusion_threshold: 55, reorder_penalty: 10}
        )
        require_positive_whole_number(
          setting_name: "recommendation.inclusion_threshold", value: recommendation.inclusion_threshold
        )
        require_whole_number_from_0_to_100(
          setting_name: "recommendation.reorder_penalty", value: recommendation.reorder_penalty
        )

        recommendation
      end

      # The section's settings from the file, over the defaults given. A section that is not
      # settings, or a setting that is not known, is recorded as an error and the rest is still
      # read, so the values that can be checked are checked.
      def build_section(settings_class:, section_name:, defaults:)
        section = @sections[section_name] || {}

        unless section.is_a?(Hash)
          add_error(
            code: :section_not_settings,
            message: "section #{section_name} must hold settings, each written as name: value",
            section: section_name
          )
          return settings_class.new(**defaults)
        end

        given_settings = section.transform_keys(&:to_sym)

        (given_settings.keys - settings_class.members).each do |setting_name|
          add_error(
            code: :unknown_setting,
            message: "unknown setting #{setting_name} in section #{section_name}",
            section: section_name,
            setting: setting_name.to_s
          )
        end

        settings_class.new(**defaults.merge(given_settings.slice(*settings_class.members)))
      end

      # A whole number (not a decimal, text, true or nothing) of at least 1.
      def require_positive_whole_number(setting_name:, value:)
        return if value.is_a?(Integer) && value >= 1

        add_error(
          code: :setting_not_positive_whole_number,
          message: "#{setting_name} must be a whole number of at least 1, got #{value.inspect}",
          setting: setting_name,
          value: value
        )
      end

      # A whole number from 0 to 100, for a score or a number of points.
      def require_whole_number_from_0_to_100(setting_name:, value:)
        return if value.is_a?(Integer) && value.between?(0, 100)

        add_error(
          code: :setting_not_whole_number_0_to_100,
          message: "#{setting_name} must be a whole number from 0 to 100, got #{value.inspect}",
          setting: setting_name,
          value: value
        )
      end

      # The word true or false, as YAML writes a yes or no setting.
      def require_true_or_false(setting_name:, value:)
        return if value == true || value == false

        add_error(
          code: :setting_not_true_or_false,
          message: "#{setting_name} must be true or false, got #{value.inspect}",
          setting: setting_name,
          value: value
        )
      end

      # One ConfigurationError for everything collected: the sentence itself for one, a list for
      # several. The entries, with their codes, are on the error.
      def raise_errors
        return if @errors.empty?

        if @errors.size == 1
          message = "#{DEFAULT_PATH}: #{@errors.first[:message]}"
        else
          lines = @errors.map { |error| "  - #{error[:message]}" }
          message = "#{DEFAULT_PATH} has #{@errors.size} errors:\n#{lines.join("\n")}"
        end

        raise ConfigurationError.new(message: message, errors: @errors)
      end
    end
  end
end
