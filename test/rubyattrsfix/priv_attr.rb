# attr-form arm (RUNTIME-REAL): the Ruby 3 INLINE-VISIBILITY idiom (RuboCop
# Style/AccessModifierDeclarations: inline). `private attr_reader :x` evaluates its
# argument first — the macro runs and the reader IS defined — then applies visibility,
# so these defs are exactly as real as the plain forms. The position gate unwraps one
# visibility call when the family call is its sole argument.
module Spike
  class PrivAttr
    private attr_reader :priv_name
    protected attr_accessor :prot_pair
    public attr_writer :pub_set
    module_function attr_accessor :mod_acc
  end
end