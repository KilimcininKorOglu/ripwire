# pair arm (attr, yaml): attr only; the yaml source is spike_names.yml beside it.
module Spike
  class AttrYaml < ApplicationRecord
    self.table_name = "spike_plain"

    attr_accessor :name
  end
end
