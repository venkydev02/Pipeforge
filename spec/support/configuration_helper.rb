# frozen_string_literal: true

# Builds a Pipeforge::Configuration from a hash of settings, by writing a temporary engine.yml.
# No arguments gives the configuration with all defaults.
#
#   build_configuration                                            # all defaults
#   build_configuration(source: {distinct_values_cap: 3})          # one setting changed
module ConfigurationHelper
  def build_configuration(settings = {})
    document = {"version" => "1.0", "engine" => deep_stringify(settings)}

    Tempfile.create(["engine", ".yml"]) do |file|
      file.write(document.to_yaml)
      file.flush
      Pipeforge::Configuration.new(path: file.path)
    end
  end

  private

  def deep_stringify(value)
    case value
    when Hash then value.to_h { |key, inner| [key.to_s, deep_stringify(inner)] }
    else value
    end
  end
end

RSpec.configure { |config| config.include ConfigurationHelper }
