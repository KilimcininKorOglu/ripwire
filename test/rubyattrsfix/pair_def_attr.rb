# pair arm (def, attr): attr_accessor comes AFTER the def, same class —
# Ruby's same-class last-definition-wins makes the attr the runtime reader.
module Spike
  class PairDefAttr < ApplicationRecord
    self.table_name = "spike_plain"

    def name
      "def"
    end

    attr_accessor :name
  end
end
