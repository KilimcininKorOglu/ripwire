# setter arm: `attribute :name` (ActiveModel::Attributes) must produce a setter.
module Spike
  class SetAttribute < ApplicationRecord
    self.table_name = "spike_plain"

    attribute :name
  end
end
