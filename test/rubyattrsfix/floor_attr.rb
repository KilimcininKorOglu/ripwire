# floor arm (STATIC-ONLY, never executed): the forms the class-DSL capture DISCLOSES as floors.
# Ruby's attr_* accepts all of these and defines real methods at runtime, but the capture
# unwraps only the call's OWN do/{ } block — so a `begin`-wrapped or modifier-`if`-guarded
# call is not class-DSL position — and defines only `simple_symbol` arguments — so a quoted
# (`:"x"` / `:'x'`), string, or splat/`%i[]` argument stays an honest nothing. Every name here
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
end
