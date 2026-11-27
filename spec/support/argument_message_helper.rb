# frozen_string_literal: true

# The sentence of an ArgumentError of the gem, built as the gem builds it.
#
#   expect { loading }.to raise_error(ArgumentError, argument_message(:mode_not_allowed, mode: :commit))
module ArgumentMessageHelper
  def argument_message(key, **arguments)
    Pipeforge::ArgumentMessages::MESSAGES.fetch(key).call(**arguments)
  end
end

RSpec.configure do |config|
  config.include ArgumentMessageHelper
end
