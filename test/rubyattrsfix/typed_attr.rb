# attr-form arm: `attribute` with type metadata — the metadata args are data,
# not defs; the symbol arg gets a getter+setter.
module Spike
  class TypedAttr < ApplicationRecord
    self.table_name = "spike_plain"

    attribute :quantity, :integer, default: 0
  end
end
