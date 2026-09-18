# setter arm: explicit `def name=` must be a setter.
module Spike
  class SetDef < ApplicationRecord
    self.table_name = "spike_plain"

    def name=(value)
      @assigned = value
    end
  end
end
