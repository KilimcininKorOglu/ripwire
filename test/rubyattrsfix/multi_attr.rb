# attr-form arm: multi-symbol attr_accessor (one call, N simple_symbol args).
module Spike
  class MultiAttr < ApplicationRecord
    self.table_name = "spike_plain"

    attr_accessor :multi_a, :multi_b
  end
end
