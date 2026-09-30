-- fnliteralcheck fixture (Lua): the module idiom binds names to function literals.
local M = {}

local function luaSink( v )
  return v + 1
end

M.luaAssigned = function( x, y )
  if x > y then
    return luaSink( x )
  end
  return luaSink( y )
end

local luaLocal = function( x )
  return luaSink( x )
end

local tbl = {
  luaField = function( x ) return luaSink( x ) end,
  luaField2 = function( x, y ) return luaSink( x + y ) end,
}

function M.useLua()
  return M.luaAssigned( 1, 2 ) + luaLocal( 1 ) + tbl.luaField( 1 ) + tbl.luaField2( 1, 2 )
end

return M
