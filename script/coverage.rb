# frozen_string_literal: true

# Runs the suite of one gem with Ruby's built-in line and branch coverage, then prints, for each
# file under that gem's lib/, the lines and branches that no example executes. Run it from the
# repository root and name the gem folder:
#
#   bundle exec ruby script/coverage.rb pipeforge
#   bundle exec ruby script/coverage.rb pipeforge-activerecord
#
# Coverage has to start before the library is loaded, which is why this is a script and not an
# option of rspec (spec_helper loads the library first). It needs no extra gem.

require "coverage"

gem_folder = ARGV.fetch(0) do
  abort "usage: bundle exec ruby script/coverage.rb <pipeforge | pipeforge-activerecord>"
end

Coverage.start(lines: true, branches: true)

require "rspec/core"

exit_status = RSpec::Core::Runner.run(
  ["--options", File.join(gem_folder, ".rspec"), File.join(gem_folder, "spec"), "--format", "progress"]
)

library_root = File.join(Dir.pwd, gem_folder, "lib") + File::SEPARATOR
lines_total = 0
lines_covered = 0
branches_total = 0
branches_covered = 0

puts
puts "Coverage of #{gem_folder}/lib/"

Coverage.result.sort.each do |file, counts|
  next unless file.start_with?(library_root)

  missed_lines = []

  counts[:lines].each_with_index do |count, index|
    next if count.nil?

    lines_total += 1

    if count.zero?
      missed_lines << index + 1
    else
      lines_covered += 1
    end
  end

  missed_branches = []

  counts[:branches].each_value do |targets|
    targets.each do |(label, _id, line), count|
      branches_total += 1

      if count.zero?
        missed_branches << "#{label}@#{line}"
      else
        branches_covered += 1
      end
    end
  end

  next if missed_lines.empty? && missed_branches.empty?

  puts "  #{file.delete_prefix(Dir.pwd + File::SEPARATOR)}"
  puts "    lines not run:    #{missed_lines.join(", ")}" unless missed_lines.empty?
  puts "    branches not run: #{missed_branches.join(", ")}" unless missed_branches.empty?
end

puts "  lines    #{lines_covered}/#{lines_total}"
puts "  branches #{branches_covered}/#{branches_total}"

exit exit_status
