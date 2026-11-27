# frozen_string_literal: true

# A consumer's program, run in a new process in a temporary project directory (see
# ConsumerProgramHelper), requires the gem.
RSpec.describe "Requiring the gem in a consumer's project" do
  subject(:program_run) { run_consumer_program(files: project_files) }

  context "when the project has a configuration file (config/pipeforge.yml)" do
    context "and the file is valid" do
      let(:project_files) { {"config/pipeforge.yml" => "engine:\n  execution:\n    chunk_size: 10\n"} }

      it "loads the gem" do
        expect(program_run).to be_success, program_run.stderr
      end
    end

    context "and the file is invalid" do
      let(:project_files) { {"config/pipeforge.yml" => "engine: [unclosed\n"} }

      it "fails to load the gem" do
        expect(program_run).not_to be_success
      end
    end
  end

  context "when the project has no configuration file" do
    let(:project_files) { {} }

    it "loads the gem" do
      expect(program_run).to be_success, program_run.stderr
    end
  end
end
