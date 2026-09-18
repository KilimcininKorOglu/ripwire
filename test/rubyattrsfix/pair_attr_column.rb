# pair arm (attr, column): attr_accessor (class method) shadows the column reader.
module Spike
  class PairAttrColumn < ApplicationRecord
    self.table_name = "spike_pair_attr_columns"

    attr_accessor :name
  end
end
