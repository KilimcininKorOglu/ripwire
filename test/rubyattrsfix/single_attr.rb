# single-source arm: `attr_accessor :name` only.
module Spike
  class SingleAttr < ApplicationRecord
    self.table_name = "spike_plain"

    attr_accessor :name
  end
end
