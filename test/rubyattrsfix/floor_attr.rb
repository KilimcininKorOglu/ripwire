# floor arm (STATIC-ONLY, never executed): the forms the class-DSL capture DISCLOSES as floors.
# Ruby's attr_* accepts all of these and defines real methods at runtime, but the capture
# unwraps only the call's OWN do/{ } block — so a `begin`-wrapped or modifier-`if`-guarded
# call is not class-DSL position — and defines only `simple_symbol` arguments — so a quoted
# (`:"x"` / `:'x'`), string, or splat/`%i[]` argument stays an honest nothing. The do-block
# BODY of an ActiveSupport::Concern (`included`/`class_methods`), of `Struct.new`/`Class.new`/
# `Module.new`, and a non-modifier `if … then … end` block are the same floor: the walk stops
# at the do_block/if node, while the runtime evaluates the block (at include time, or on the
# new class/module, or at class-definition time) and defines the accessors. Every name here
# must remain undefinable; that silence is stated, pinned, and deliberate.
module Spike
  class FloorGuarded
    begin
      attr_accessor :begin_guarded
    end

    attr_writer :if_guarded if true
  end

  class FloorDynamic
    attr_accessor :"dq_name"
    attr_reader :'sq_name'
    attr_writer "string_name"
    attr_reader *%i[splat_a splat_b]
  end

  class FloorConcern
    included do
      attr_accessor :concern_included
    end

    class_methods do
      attr_writer :concern_class_method
    end

    Struct.new(:s) do
      attr_accessor :struct_attr
    end

    Class.new do
      attr_reader :classnew_attr
    end

    if true then
      attr_reader :ifthen_attr
    end
  end
end
