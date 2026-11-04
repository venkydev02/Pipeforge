# frozen_string_literal: true

# A consumer's program, run in a new process in a temporary project directory (see
# ConsumerProgramHelper), requires the gem of each adapter.
RSpec.describe "Requiring the gem in a consumer's project" do
  # The entry file of every adapter, found from the folders of lib/pipeforge/adapters, so a new
  # adapter is checked without a change to this file.
  let(:adapter_entry_files) do
    repository_root = File.expand_path("../..", __dir__)
    adapter_folders = Dir[File.join(repository_root, "lib", "pipeforge", "adapters", "*")].select { |path| File.directory?(path) }

    adapter_folders.map { |folder| "pipeforge-#{File.basename(folder)}" }.sort
  end

  context "when the project has a configuration file (config/pipeforge.yml)" do
    context "that is valid" do
      let(:project_files) { {"config/pipeforge.yml" => "engine:\n  execution:\n    chunk_size: 10\n"} }

      it "loads the gem for every adapter" do
        expect(failures_of_adapters(files: project_files)).to eq({})
      end
    end

    context "that is invalid" do
      let(:project_files) { {"config/pipeforge.yml" => "engine: [unclosed\n"} }

      it "fails to load the gem for every adapter" do
        expect(failures_of_adapters(files: project_files).keys).to eq(adapter_entry_files)
      end
    end
  end

  context "when the project has no configuration file" do
    let(:project_files) { {} }

    it "loads the gem for every adapter" do
      expect(failures_of_adapters(files: project_files)).to eq({})
    end
  end

  # The program run of each adapter, keyed by its entry file.
  def program_runs_of_adapters(files:)
    program_runs = {}

    adapter_entry_files.each do |entry_file|
      program_runs[entry_file] = run_consumer_program(files: files, entry_file: entry_file)
    end

    program_runs
  end

  # The error output of each adapter whose program ended with an error, keyed by its entry file.
  def failures_of_adapters(files:)
    failures = {}

    program_runs_of_adapters(files: files).each do |entry_file, program_run|
      failures[entry_file] = program_run.stderr unless program_run.success?
    end

    failures
  end
end
