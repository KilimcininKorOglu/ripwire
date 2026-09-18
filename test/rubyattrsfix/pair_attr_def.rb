# pair arm (attr, def): the def comes AFTER the attr_accessor and reclaims
# the reader; the attr's writer survives.
module Spike
  class PairAttrDef < ApplicationRecord
    self.table_name = "spike_plain"

    attr_accessor :name

    def name
      "def"
    end
  end
end
