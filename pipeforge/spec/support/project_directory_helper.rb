# frozen_string_literal: true

require "fileutils"
require "tmpdir"

# Runs a block in an empty temporary directory that stands for the root of a project, because
# the engine reads its settings from the conventional file, config/pipeforge.yml, in the
# directory the program runs in. When +config+ is given, it is written to that file first.
#
#   in_project_directory(config: "engine:\n  execution:\n    batch_size: 10\n") { ... }
module ProjectDirectoryHelper
  def in_project_directory(config: nil)
    Dir.mktmpdir do |directory|
      Dir.chdir(directory) do
        write_project_config(text: config) unless config.nil?
        yield
      end
    end
  end

  private

  def write_project_config(text:)
    FileUtils.mkdir_p(File.dirname(Pipeforge::Configuration::DEFAULT_PATH))
    File.write(Pipeforge::Configuration::DEFAULT_PATH, text)
  end
end

RSpec.configure { |config| config.include ProjectDirectoryHelper }
