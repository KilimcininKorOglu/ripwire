# attr-form arm (STATIC-ONLY, never executed): the plural `attributes` with a
# do-block is third-party-DSL syntax — base Rails 8.1 raises NoMethodError
# (measured, see USECASES.md). Valid Ruby syntax; exists so the static capture can
# prove the do-block body is WALKED BUT DEFINES NOTHING (the block's `sub` and
# assignments must not become symbols).
module Spike
  class BlockAttr
    attributes :block_a do |sub|
      sub.default = 1
    end

    attributes :multi_p1, :multi_p2
  end
end
