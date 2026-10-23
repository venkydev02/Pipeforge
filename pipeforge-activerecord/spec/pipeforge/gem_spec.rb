# frozen_string_literal: true

RSpec.describe "the pipeforge-activerecord gem" do
  let(:gemspec) do
    Gem::Specification.load(File.expand_path("../../pipeforge-activerecord.gemspec", __dir__))
  end

  it "has its own version, kept in one place" do
    expect(gemspec.version.to_s).to eq(Pipeforge::ActiveRecordAdapter::VERSION)
  end

  it "works with the version of the core that is in this repository" do
    core = gemspec.runtime_dependencies.find { |dependency| dependency.name == "pipeforge" }

    expect(core.requirement).to be_satisfied_by(Gem::Version.new(Pipeforge::VERSION))
  end

  it "depends on activerecord" do
    expect(gemspec.runtime_dependencies.map(&:name)).to include("activerecord")
  end
end
