# frozen_string_literal: true

# Gives the adapter registry a second adapter, named "spec_adapter", for one example.
module AdapterRegistryHelper
  # activerecord stays: the suite loads the default settings again while the constant is still replaced.
  def add_spec_adapter(class_name: "SpecAdapter", path: "spec_adapter")
    stub_const(
      "Pipeforge::AdapterRegistry::ADAPTERS",
      Pipeforge::AdapterRegistry::ADAPTERS.merge("spec_adapter" => {class_name: class_name, path: path})
    )
  end
end

RSpec.configure do |config|
  config.include AdapterRegistryHelper
end
