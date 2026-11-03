# frozen_string_literal: true

require "open3"
require "rbconfig"

# The core works without any database library: the target is reached only through an adapter, which
# lives in its own folder under lib/pipeforge/adapters/.
RSpec.describe "the core" do
  let(:repository_root) { File.expand_path("../..", __dir__) }

  it "loads without loading ActiveRecord or ActiveSupport" do
    script = 'require "pipeforge"; exit(defined?(ActiveRecord).nil? && defined?(ActiveSupport).nil? ? 0 : 1)'

    output, status = Open3.capture2e(RbConfig.ruby, "-I", File.join(repository_root, "lib"), "-e", script)

    expect(status.success?).to be(true), "the core loaded a database library: #{output}"
  end

  it "names no ActiveRecord or ActiveSupport constant in its code" do
    offending_lines = []

    core_files.each do |file|
      File.readlines(file).each_with_index do |line, index|
        next if line.lstrip.start_with?("#")

        offending_lines << "#{file.delete_prefix(repository_root + "/")}:#{index + 1}" if line.match?(/ActiveRecord|ActiveSupport/)
      end
    end

    expect(offending_lines).to eq([])
  end

  # The files of lib/ that are not an adapter's: the adapters' folder and the file Bundler requires for the
  # gem of an adapter are left out.
  def core_files
    adapter_files = Dir[File.join(repository_root, "lib", "pipeforge", "adapters", "**", "*.rb")] +
      [File.join(repository_root, "lib", "pipeforge-activerecord.rb")]

    (Dir[File.join(repository_root, "lib", "**", "*.rb")] - adapter_files).sort
  end
end
