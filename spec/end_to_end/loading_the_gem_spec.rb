# frozen_string_literal: true

RSpec.describe "A user's program requiring the installed gem" do
  before(:context) { @gem_home = install_built_gem }
  after(:context) { FileUtils.remove_entry(@gem_home) }

  subject(:program_run) { run_consumer_program(program_name: "loading", files: project_files, gem_home: @gem_home) }

  context "when config/pipeforge.yml is valid" do
    let(:project_files) { {"config/pipeforge.yml" => "engine:\n  execution:\n    chunk_size: 10\n"} }

    it "ends without an error" do
      expect(program_run).to be_success, program_run.stderr
    end
  end

  context "when there is no config/pipeforge.yml" do
    let(:project_files) { {} }

    it "ends without an error" do
      expect(program_run).to be_success, program_run.stderr
    end

    it "loads the installed gem" do
      expect(program_run.report.fetch("loaded_from")).to start_with(File.realpath(@gem_home))
    end
  end

  context "when config/pipeforge.yml is not valid YAML" do
    let(:project_files) { {"config/pipeforge.yml" => "engine: [unclosed\n"} }

    it "ends with an error" do
      expect(program_run).not_to be_success
    end

    it "names config/pipeforge.yml in the error" do
      expect(program_run.stderr).to include("config/pipeforge.yml")
    end
  end
end
