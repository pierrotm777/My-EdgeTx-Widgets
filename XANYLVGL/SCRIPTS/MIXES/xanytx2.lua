-- xanytx2.lua - XANY FM-bank wrapper
-- ID=2 -> FM1
FM_INDEX = 1
local common = loadScript("/SCRIPTS/MIXES/xanytx_common.lua")()
return {
  input = common.input,
  output = { "XANY2" },
  init = common.init,
  run = function(event)
    local _, o2 = common.run(event)
    return o2
  end
}
