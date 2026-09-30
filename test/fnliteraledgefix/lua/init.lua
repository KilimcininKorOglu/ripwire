-- A non-`local` nested `function lua_helper` is a GLOBAL once M.setup() has run: M.run's call means THIS one.
local M = {}
function M.setup()
  function lua_helper(x) return x + 1 end
end
function M.run()
  return lua_helper(1)
end
return M
