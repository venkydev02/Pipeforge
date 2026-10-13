# frozen_string_literal: true

# Matches a TypeChecker against texts. The positive form needs every text to fit; the negated
# form needs none of them to fit. A failure names the texts that broke it.
#
#   expect(type_checker).to fit_text("42", "-7")
#   expect(type_checker).not_to fit_text("4.5", "abc")
RSpec::Matchers.define :fit_text do |*texts|
  match do |type_checker|
    @not_fitting = texts.reject { |text| type_checker.fits?(text: text) }
    @not_fitting.empty?
  end

  match_when_negated do |type_checker|
    @fitting = texts.select { |text| type_checker.fits?(text: text) }
    @fitting.empty?
  end

  failure_message do
    "expected every text to fit, but these do not: #{@not_fitting.map(&:inspect).join(", ")}"
  end

  failure_message_when_negated do
    "expected no text to fit, but these do: #{@fitting.map(&:inspect).join(", ")}"
  end

  description do
    "fit #{texts.map(&:inspect).join(", ")}"
  end
end
