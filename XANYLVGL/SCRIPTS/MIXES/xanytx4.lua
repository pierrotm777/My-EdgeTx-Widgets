-- xanytx4.lua - XANY FM-bank wrapper
-- ID=4 -> FM3
FM_INDEX = 3
local common = loadScript("/SCRIPTS/MIXES/xanytx_common.lua")()
return {
  input = common.input,
  output = { "XANY4" },
  init = common.init,
  run = function(event)
    local _, _, _, o4 = common.run(event)
    return o4
  end
}
