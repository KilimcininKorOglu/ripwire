require_relative "../a/list"
require_relative "../b/tree"

def report(rows)
  list = LinkedList.new
  rows.each { |r| puts r }
  list
end
