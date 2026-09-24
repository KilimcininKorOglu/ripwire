# setter arm: attr_writer must produce a setter.
module Spike
  class SetWriter < ApplicationRecord
    self.table_name = "spike_plain"

    attr_writer :name
  end
end
