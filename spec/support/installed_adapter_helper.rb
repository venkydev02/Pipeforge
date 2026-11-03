# frozen_string_literal: true

# The real adapter installs itself in Pipeforge::TargetAdapter when the suite loads. A spec that needs no
# adapter takes it away for the length of one example and puts the original back.
module InstalledAdapterHelper
  def without_installed_adapter
    original = Pipeforge::TargetAdapter.instance_variable_get(:@adapter)
    Pipeforge::TargetAdapter.install(adapter: nil)

    yield
  ensure
    Pipeforge::TargetAdapter.install(adapter: original)
  end
end

RSpec.configure { |config| config.include InstalledAdapterHelper }
