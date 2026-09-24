# attr-form arm: a comment BEFORE the first argument is not that argument. tree-sitter-ruby gives the
# comment its own named child in the argument list, so the singular `attribute` must skip it and still
# take :cmt_name (getter + setter); the type after it stays metadata.
module Spike
  class CommentAttr < ApplicationRecord
    self.table_name = "spike_plain"

    attribute( # the name comes on the next line
      :cmt_name, :string )
  end
end
