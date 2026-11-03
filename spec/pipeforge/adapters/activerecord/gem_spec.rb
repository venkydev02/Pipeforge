# frozen_string_literal: true

require "fileutils"
require "tmpdir"

RSpec.describe "the pipeforge-activerecord gem" do
  let(:repository_root) { File.expand_path("../../../..", __dir__) }
  let(:gemspec) { Gem::Specification.load(File.join(repository_root, "pipeforge-activerecord.gemspec")) }

  it "takes the version of the core it carries" do
    expect(gemspec.version.to_s).to eq(Pipeforge::VERSION)
  end

  it "depends on smarter_csv and activerecord, and on no other gem" do
    expect(gemspec.runtime_dependencies.map(&:name)).to contain_exactly("smarter_csv", "activerecord")
  end

  it "carries the files of the core" do
    expect(gemspec.files).to include("lib/pipeforge.rb", "lib/pipeforge/engine.rb")
  end

  it "carries the files of the adapter, and the file Bundler requires for the gem" do
    expect(gemspec.files).to include("lib/pipeforge/adapters/activerecord/adapter.rb", "lib/pipeforge-activerecord.rb")
  end

  context "when the repository also holds another adapter" do
    let(:files_of_the_gem) do
      Dir.mktmpdir do |directory|
        write_file(directory: directory, path: "lib/pipeforge/version.rb")
        write_file(directory: directory, path: "lib/pipeforge.rb")
        write_file(directory: directory, path: "lib/pipeforge/engine.rb")
        write_file(directory: directory, path: "lib/pipeforge-activerecord.rb")
        write_file(directory: directory, path: "lib/pipeforge/adapters/activerecord/adapter.rb")
        write_file(directory: directory, path: "lib/pipeforge-mysql.rb")
        write_file(directory: directory, path: "lib/pipeforge/adapters/mysql/adapter.rb")
        write_file(directory: directory, path: "lib/pipeforge/adapters/mysql/model.rb")
        FileUtils.cp(File.join(repository_root, "pipeforge-activerecord.gemspec"), directory)

        Dir.chdir(directory) do
          Gem::Specification.load(File.join(directory, "pipeforge-activerecord.gemspec")).files
        end
      end
    end

    it "carries the core and its own adapter" do
      expect(files_of_the_gem).to include(
        "lib/pipeforge.rb", "lib/pipeforge/engine.rb", "lib/pipeforge-activerecord.rb",
        "lib/pipeforge/adapters/activerecord/adapter.rb"
      )
    end

    it "carries no folder and no entry file of the other adapter" do
      expect(files_of_the_gem.grep(/mysql/)).to eq([])
    end

    def write_file(directory:, path:)
      full_path = File.join(directory, path)
      FileUtils.mkdir_p(File.dirname(full_path))
      File.write(full_path, "")
    end
  end

  it "carries no spec file" do
    expect(gemspec.files.grep(/spec/)).to eq([])
  end

  it "puts only lib on the load path" do
    expect(gemspec.require_paths).to eq(["lib"])
  end

  it "installs the ActiveRecord adapter in the core when the file Bundler requires for the gem is loaded" do
    expect(Pipeforge::TargetAdapter.instance_variable_get(:@adapter)).to be_a(Pipeforge::ActiveRecordAdapter)
  end
end
