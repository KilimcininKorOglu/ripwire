# NEGATIVE arm, static only (never executed: it would raise). `module_function attr_accessor :mod_acc` is
# not an inline-visibility form. In a class, Class undefines module_function (NoMethodError); in a module,
# module_function refuses the [:mod_acc, :mod_acc=] array attr_accessor returns (TypeError). Measured on
# Ruby 4.0.7. No running program spells it, so the capture does not unwrap it and it defines nothing.
module Spike
  module ModFnAttr
    module_function attr_accessor :mod_acc
  end
end
