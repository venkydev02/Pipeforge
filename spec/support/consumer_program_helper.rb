# frozen_string_literal: true

require "fileutils"
require "open3"
require "rbconfig"
require "tmpdir"

# Runs a Ruby program the way a consumer's application does: in an empty temporary directory that
# stands for the root of the project, in a new process with the repository's lib on the load path.
# The files the program needs (the configuration file, a source file) are written first, each at
# the path given. Included in the specs of spec/integration only.
module ConsumerProgramHelper
  # What a program left behind: what it printed, what it reported as an error and how it ended.
  ConsumerProgramRun = Data.define(:stdout, :stderr, :exit_status) do
    # @return [Boolean] whether the program ended without an error
    def success?
      exit_status.zero?
    end
  end

  # @param files [Hash{String => String}] path relative to the project directory => content, for
  #   example "config/pipeforge.yml" => "engine:\n  execution:\n    chunk_size: 10\n"
  # @param entry_file [String] the entry file of the adapter gem the program requires:
  #   "pipeforge-activerecord" (the default), or that of a future adapter. A consumer never requires
  #   the core alone: it comes inside the adapter gem.
  # @return [ConsumerProgramRun]
  def run_consumer_program(files: {}, entry_file: "pipeforge-activerecord")
    Dir.mktmpdir do |project_directory|
      files.each do |path, content|
        write_project_file(project_directory: project_directory, path: path, content: content)
      end

      write_project_file(project_directory: project_directory, path: "program.rb", content: "require #{entry_file.inspect}\n")

      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby, "-I", File.join(consumer_program_repository_root, "lib"), "program.rb",
        chdir: project_directory
      )

      ConsumerProgramRun.new(stdout: stdout, stderr: stderr, exit_status: status.exitstatus)
    end
  end

  private

  def write_project_file(project_directory:, path:, content:)
    full_path = File.join(project_directory, path)
    FileUtils.mkdir_p(File.dirname(full_path))
    File.write(full_path, content)
  end

  def consumer_program_repository_root
    File.expand_path("../..", __dir__)
  end
end

RSpec.configure { |config| config.include ConsumerProgramHelper, type: :integration }
