-- xanytx1.lua - XANY FM-bank wrapper
-- ID=1 -> FM0
FM_INDEX = 0
local common = loadScript("/SCRIPTS/MIXES/xanytx_common.lua")()
return {
  input = common.input,
  output = { "XANY1" },
  init = common.init,
  run = function(event)
    local o1 = common.run(event)
    return o1
  end
}
