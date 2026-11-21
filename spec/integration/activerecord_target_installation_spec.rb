# frozen_string_literal: true

# The entry file of the ActiveRecord gem is loaded with the suite (see spec_helper), so the engine already has the
# target class that the gem installed.
RSpec.describe "The ActiveRecord gem installing its target in the engine" do
  it "gives the engine the ActiveRecordTarget class" do
    expect(Pipeforge::Engine.target_class).to be(Pipeforge::ActiveRecordTarget)
  end
end
