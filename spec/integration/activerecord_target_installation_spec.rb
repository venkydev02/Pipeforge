# frozen_string_literal: true

# The gem is loaded with the suite (see spec_helper), so the engine already has the target class of the adapter
# that the default settings name.
RSpec.describe "Requiring the gem, with the default settings" do
  it "installs the ActiveRecordTarget class in the engine" do
    expect(Pipeforge::Engine.target_class).to be(Pipeforge::ActiveRecordTarget)
  end
end
