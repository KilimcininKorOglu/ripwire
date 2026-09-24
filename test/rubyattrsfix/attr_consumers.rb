# Hand-written arm: OUTSIDE call sites for the attr family, plus the
# negative gates the class-DSL-position capture must respect.
#
# Reads/writes here are the `--uses` rows the gate asserts. The write targets on SetReader
# bind to `name=` (the name-based setter ref); attr_reader defines no `name=` def, so the
# def set for `name=` comes from the attr_writer/attr_accessor/attribute/def-name= files only.

def read_single_attr
  a = Spike::SingleAttr.new
  a.name = "x"
  a.name
end

def write_writer(value)
  w = Spike::SetWriter.new
  w.name = value
end

def read_reader
  Spike::SetReader.new.name
end

def read_multi
  m = Spike::MultiAttr.new
  m.multi_a = 1
  m.multi_a
end

# NEGATIVE arms — the capture must NOT fire on these:
#   receiver-qualified family calls are somebody's own methods (rubyNamedDirective posture)
#   method bodies are not class-body level
#   file top level is not class-body level
def method_body_attr_reader
  attr_reader :inside_method
  @inside_method
end

def receiver_qualified
  io = StringIO.new
  io.attr_writer :qualified_target
end

attr_reader :file_level_target
