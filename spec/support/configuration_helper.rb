# frozen_string_literal: true

# Makes the engine use the given settings, by writing them to config/pipeforge.yml in a
# temporary project directory and loading them. No arguments gives the defaults. After every
# example the defaults are loaded again, from the directory the suite started in, which has no
# such file, so one example's settings never reach the next.
#
#   use_settings                                    # all defaults
#   use_settings(source: {distinct_values_cap: 3})  # one setting changed
module ConfigurationHelper
  SUITE_DIRECTORY = Dir.pwd

  def use_settings(settings = {})
    document = {"version" => "1.0", "engine" => deep_stringify(settings)}

    in_project_directory(config: document.to_yaml) { Pipeforge::Configuration.load }
  end

  private

  def deep_stringify(value)
    case value
    when Hash then value.to_h { |key, inner| [key.to_s, deep_stringify(inner)] }
    else value
    end
  end
end

RSpec.configure do |config|
  config.include ConfigurationHelper
  config.after { Dir.chdir(ConfigurationHelper::SUITE_DIRECTORY) { Pipeforge::Configuration.load } }
end
