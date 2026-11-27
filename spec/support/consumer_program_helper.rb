# frozen_string_literal: true

require "fileutils"
require "open3"
require "rbconfig"
require "tmpdir"

# Runs a Ruby program the way a user's application does: in an empty temporary directory that stands for the
# root of the project, in a new process. The program finds the gem in the repository's lib, or in a folder it
# was installed into. Included in the specs of spec/end_to_end only.
module ConsumerProgramHelper
  # What a program left behind: what it printed, what it reported as an error and how it ended.
  ConsumerProgramRun = Data.define(:stdout, :stderr, :exit_status) do
    # @return [Boolean] whether the program ended without an error
    def success?
      exit_status.zero?
    end

    # @return [Hash] the JSON the program printed
    # @raise [RuntimeError] the program ended with an error
    def report
      raise "the program failed:\n#{stderr}" unless success?

      JSON.parse(stdout)
    end
  end

  # @param program_name [String] a file of spec/end_to_end/programs, without ".rb"
  # @param files [Hash{String => String}] path relative to the project directory => content, for
  #   example "config/pipeforge.yml" => "engine:\n  execution:\n    chunk_size: 10\n"
  # @param gem_home [String, nil] the folder the built gem was installed into (see {#install_built_gem});
  #   nil runs the program on the repository's lib
  # @return [ConsumerProgramRun]
  def run_consumer_program(program_name:, files: {}, gem_home: nil)
    Dir.mktmpdir do |project_directory|
      files.each do |path, content|
        write_project_file(project_directory: project_directory, path: path, content: content)
      end

      Dir[File.join(consumer_program_folder, "*.rb")].each { |program| FileUtils.cp(program, project_directory) }

      if gem_home.nil?
        capture_program(project_directory: project_directory, program_name: program_name, environment: {}, load_path: repository_lib)
      else
        environment = {"GEM_HOME" => gem_home, "GEM_PATH" => [gem_home, *Gem.path].join(File::PATH_SEPARATOR)}

        # Without the suite's Bundler settings, so the program resolves the installed gem as a user's would.
        Bundler.with_unbundled_env do
          capture_program(project_directory: project_directory, program_name: program_name, environment: environment, load_path: nil)
        end
      end
    end
  end

  # Builds the gem from its gemspec and installs it, without its dependencies, into a new folder.
  #
  # @return [String] the folder, which the caller removes
  def install_built_gem
    gem_home = Dir.mktmpdir
    gem_file = File.join(gem_home, "pipeforge.gem")

    run_gem_command("build", "pipeforge.gemspec", "--output", gem_file)
    run_gem_command("install", "--local", "--ignore-dependencies", "--no-document", "--install-dir", gem_home, gem_file)

    gem_home
  end

  private

  def capture_program(project_directory:, program_name:, environment:, load_path:)
    command = [RbConfig.ruby]
    command.push("-I", load_path) unless load_path.nil?
    command.push("#{program_name}.rb")

    stdout, stderr, status = Open3.capture3(environment, *command, chdir: project_directory)

    ConsumerProgramRun.new(stdout: stdout, stderr: stderr, exit_status: status.exitstatus)
  end

  def run_gem_command(*arguments)
    output, status = Open3.capture2e(RbConfig.ruby, "-S", "gem", *arguments, chdir: repository_root)

    raise "gem #{arguments.first} failed:\n#{output}" unless status.success?
  end

  def write_project_file(project_directory:, path:, content:)
    full_path = File.join(project_directory, path)
    FileUtils.mkdir_p(File.dirname(full_path))
    File.write(full_path, content)
  end

  def repository_root
    File.expand_path("../..", __dir__)
  end

  def repository_lib
    File.join(repository_root, "lib")
  end

  def consumer_program_folder
    File.join(repository_root, "spec", "end_to_end", "programs")
  end
end

RSpec.configure { |config| config.include ConsumerProgramHelper, type: :end_to_end }
