# attr-form arm (RUNTIME-REAL, plain Ruby): `class << self` inside a class opens THAT class's singleton, so
# its accessors are class-level accessors of SingletonAttr and scope to it. `class << Registry` opens ANOTHER
# object's singleton: `Spike::Registry.other_tok` exists and `Spike::SingletonAttr.other_tok` does not, so
# ripwire, whose scope would name the enclosing class, defines nothing for it (a disclosed floor).
module Spike
  class Registry; end

  class SingletonAttr
    class << self
      attr_accessor :self_tok
    end

    class << Registry
      attr_accessor :other_tok
    end
  end
end
