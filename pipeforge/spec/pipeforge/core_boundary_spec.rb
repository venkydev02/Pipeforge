# frozen_string_literal: true

require "open3"
require "rbconfig"

# The core gem works without any database library: the target is reached only through an
# adapter gem.
RSpec.describe "the core gem" do
  let(:gem_root) { File.expand_path("../..", __dir__) }

  it "loads without loading ActiveRecord or ActiveSupport" do
    script = 'require "pipeforge"; exit(defined?(ActiveRecord).nil? && defined?(ActiveSupport).nil? ? 0 : 1)'

    output, status = Open3.capture2e(RbConfig.ruby, "-I", File.join(gem_root, "lib"), "-e", script)

    expect(status.success?).to be(true), "the core loaded a database library: #{output}"
  end

  it "depends only on smarter_csv at run time" do
    gemspec = Gem::Specification.load(File.join(gem_root, "pipeforge.gemspec"))

    expect(gemspec.runtime_dependencies.map(&:name)).to eq(["smarter_csv"])
  end
end
