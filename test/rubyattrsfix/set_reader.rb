# setter arm: attr_reader must NOT produce a setter.
module Spike
  class SetReader < ApplicationRecord
    self.table_name = "spike_plain"

    attr_reader :name
  end
end
