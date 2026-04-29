-- xanytx3.lua - XANY FM-bank wrapper
-- ID=3 -> FM2
FM_INDEX = 2
local common = loadScript("/SCRIPTS/MIXES/xanytx_common.lua")()
return {
  input = common.input,
  output = { "XANY3" },
  init = common.init,
  run = function(event)
    local _, _, o3 = common.run(event)
    return o3
  end
}
