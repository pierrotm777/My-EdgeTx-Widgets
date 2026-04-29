-- XANYLVGL - settings.lua LVGL
-- Mise en forme inspirée de XANYCTL :
--   - Colonne gauche : Type / Titre / Curseur / Sauver
--   - Centre : édition du bouton courant
--   - Colonne droite : Instance / Bouton
-- IMPORTANT :
--   - Aucun lcd.*
--   - textEdit LVGL => clavier LVGL natif
--   - libGUI keyboard.lua n'est plus nécessaire ici

local function ctx()
  return (_G and (_G.XANYCTL_SETTINGS_CONTEXT or _G.XANYLVGL_SETTINGS_CONTEXT)) or {}
end

local function getOffButtonColor()
  local c = ctx()
  local opts = c and c.options
  return (opts and opts.OffCol) or COLOR_THEME_SECONDARY1 or GREY
end

local DEFAULT_TXT = {
  SETTINGS_MODEL = "Modèle: ",
  SETTINGS_INSTANCE = "INSTANCE",
  SETTINGS_BUTTON = "BOUTON",
  SETTINGS_TYPE = "Type",
  SETTINGS_TITLE = "Titre",
  SETTINGS_SLIDER = "Curseur",
  SETTINGS_SAVE = "Sauver",
  SETTINGS_LOGO = "LOGO",
}

local TXT = DEFAULT_TXT

local TYPE_VALUES = { "toggle", "momentary" }

local editor = {
  instanceId = 1,
  buttonIndex = 1,
  cfg = nil,
  logoPickerOpen = false,
}

local function loadTexts()
  TXT = DEFAULT_TXT
  local candidates = {
    "/WIDGETS/XANYLVGL/Langs/fr/lang.lua",
  }

  for _, path in ipairs(candidates) do
    local chunk = loadScript(path)
    if chunk then
      local ok, t = pcall(chunk)
      if ok and type(t) == "table" then
        TXT = t
        return
      end
    end
  end
end

local function getModelName()
  local mi = model.getInfo()
  return (mi and mi.name) or "MODELE"
end

local function getConfigPath()
  return "/WIDGETS/XANYLVGL/" .. getModelName() .. ".lua"
end

local function normalizeButton(btn, idx)
  btn = btn or {}
  if type(btn.label) ~= "string" then btn.label = tostring(idx) end
  if btn.type ~= "momentary" then btn.type = "toggle" end
  if type(btn.logo) ~= "string" then btn.logo = "" end
  return btn
end

local function ensureConfig()
  editor.cfg = editor.cfg or {}
  editor.cfg.instances = editor.cfg.instances or {}

  for instId = 1, 4 do
    local inst = editor.cfg.instances[instId]
    if type(inst) ~= "table" then
      inst = {
        title = "INSTANCE " .. tostring(instId),
        buttons = {},
        prop = { label = "PROP", logo = "" },
      }
      editor.cfg.instances[instId] = inst
    end

    if type(inst.title) ~= "string" or inst.title == "" then
      inst.title = "INSTANCE " .. tostring(instId)
    end

    inst.buttons = inst.buttons or {}
    for i = 1, 16 do
      inst.buttons[i] = normalizeButton(inst.buttons[i], i)
    end

    inst.prop = inst.prop or { label = "PROP", logo = "" }
    if type(inst.prop.label) ~= "string" or inst.prop.label == "" then
      inst.prop.label = "PROP"
    end
    if type(inst.prop.logo) ~= "string" then
      inst.prop.logo = ""
    end
  end
end

local function loadConfig()
  local path = getConfigPath()
  local chunk = loadScript(path)
  if not chunk then
    editor.cfg = { instances = {} }
    ensureConfig()
    return true
  end

  local ok, cfg = pcall(chunk)
  if not ok or type(cfg) ~= "table" then
    editor.cfg = { instances = {} }
    ensureConfig()
    return false
  end

  editor.cfg = cfg
  ensureConfig()
  return true
end

local function getInstance()
  ensureConfig()
  return editor.cfg.instances[editor.instanceId]
end

local function getButton()
  local inst = getInstance()
  return inst.buttons[editor.buttonIndex], inst
end

local function getCurrentButtonState()
  ensureConfig()
  local inst = editor.cfg.instances[editor.instanceId]
  if type(inst) ~= "table" then
    inst = {
      title = "INSTANCE " .. tostring(editor.instanceId),
      buttons = {},
      prop = { label = "PROP", logo = "" },
    }
    editor.cfg.instances[editor.instanceId] = inst
  end
  inst.buttons = inst.buttons or {}
  inst.buttons[editor.buttonIndex] = normalizeButton(inst.buttons[editor.buttonIndex], editor.buttonIndex)
  return inst.buttons[editor.buttonIndex], inst
end

local function escapeString(s)
  s = tostring(s or "")
  s = string.gsub(s, "\\", "\\\\")
  s = string.gsub(s, "\n", "\\n")
  s = string.gsub(s, "\r", "\\r")
  s = string.gsub(s, '"', '\\"')
  return s
end

local function buildConfigContent(cfg)
  local lines = {}
  lines[#lines + 1] = "local cfg = {}"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "cfg.instances = {"

  local instances = (cfg and cfg.instances) or {}

  for instId = 1, 4 do
    local inst = instances[instId] or {}
    local buttons = inst.buttons or {}
    local prop = inst.prop or {}

    lines[#lines + 1] = "  [" .. instId .. "] = {"
    lines[#lines + 1] = '    title = "' .. escapeString(inst.title or ("INSTANCE " .. tostring(instId))) .. '",'
    lines[#lines + 1] = "    buttons = {"

    for i = 1, 16 do
      local b = normalizeButton(buttons[i], i)
      lines[#lines + 1] =
        '      { label="' .. escapeString(b.label or tostring(i)) ..
        '",  type="' .. escapeString(b.type or "toggle") ..
        '",    logo="' .. escapeString(b.logo or "") .. '" },'
    end

    lines[#lines + 1] = "    },"
    lines[#lines + 1] =
      '    prop = { label = "' .. escapeString(prop.label or ("PROP " .. tostring(instId))) ..
      '", logo="' .. escapeString(prop.logo or "") .. '" },'
    lines[#lines + 1] = "  },"
    lines[#lines + 1] = ""
  end

  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "return cfg"
  return table.concat(lines, "\n")
end

local function saveConfig()
  ensureConfig()
  local f = io and io.open and io.open(getConfigPath(), "w")
  if not f then return false end

  local content = buildConfigContent(editor.cfg)
  local ok = false
  if io and io.write then
    ok = pcall(io.write, f, content)
  elseif f and f.write then
    ok = pcall(f.write, f, content)
  end

  if io and io.close then
    pcall(io.close, f)
  elseif f and f.close then
    pcall(f.close, f)
  end

  return ok
end

local function closePage()
  local c = ctx()
  if c and type(c.closeSettings) == "function" then
    c.closeSettings()
  else
    local w = c and c.widget
    if w then
      w.settingsScreenOpen = false
    end
    if lvgl and type(lvgl.clear) == "function" then
      lvgl.clear()
    end
  end

  if lvgl and type(lvgl.exitFullScreen) == "function" then
    pcall(lvgl.exitFullScreen)
  end
end

local function typeIndexOf(s)
  if s == "momentary" then return 2 end
  return 1
end

local function typeValueOf(i)
  return TYPE_VALUES[i] or "toggle"
end

local function cycleInstance(step)
  editor.instanceId = editor.instanceId + step
  if editor.instanceId < 1 then editor.instanceId = 4 end
  if editor.instanceId > 4 then editor.instanceId = 1 end
end

local function cycleButton(step)
  editor.buttonIndex = editor.buttonIndex + step
  if editor.buttonIndex < 1 then editor.buttonIndex = 16 end
  if editor.buttonIndex > 16 then editor.buttonIndex = 1 end
end

local function getLogoPath(logoName)
  if not logoName or logoName == "" then
    return nil
  end
  if string.sub(logoName, 1, 1) == "/" then
    return logoName
  end
  return "/WIDGETS/XANYLVGL/Logos/" .. logoName
end

local function reopenPage()
  if lvgl and type(lvgl.clear) == "function" then
    lvgl.clear()
  end
  open()
end

local function getLogoList()
  local list = {}
  local seen = {}

  if type(dir) == "function" then
    local ok, iterator = pcall(dir, "/WIDGETS/XANYLVGL/Logos")
    if ok and iterator then
      for entry in iterator do
        local name = nil
        if type(entry) == "string" then
          name = entry
        elseif type(entry) == "table" then
          name = entry.name or entry[1]
        end
        if name and name ~= "." and name ~= ".." then
          local lower = string.lower(name)
          if string.match(lower, "%.png$") and not seen[name] then
            seen[name] = true
            list[#list + 1] = name
          end
        end
      end
    end
  end

  table.sort(list)
  return list
end

local function buildLeftColumn(btn, inst)
  return {
    type = "box",
    x = 4,
    y = 0,
    w = 108,
    h = 240,
    children = {
	
	  { type = "label", x = 0, y = 0, w = 120, text = TXT.SETTINGS_TYPE or "Type" },
      {
        type = "button",
        x = 0, y = 22, w = 104, h = 32,
        text = tostring(btn.type or "toggle"),
        color = getOffButtonColor(),
        press = function()
          if btn.type == "momentary" then
            btn.type = "toggle"
          else
            btn.type = "momentary"
          end
          ensureConfig()
          reopenPage()
        end
      },
	  
	  { type = "label", x = 0, y = 55, w = 120, text = TXT.SETTINGS_TITLE or "Titre" },
	  {
		type = "textEdit",
		x = 0, y = 77, w = 104,
		value = inst.title or "",
		set = function(v)
		  inst.title = tostring(v or "")
		end
	  },

	  { type = "label", x = 0, y = 110, w = 120, text = TXT.SETTINGS_SLIDER or "Curseur" },
	  {
		type = "textEdit",
		x = 0, y = 132, w = 104,
		value = (inst.prop and inst.prop.label) or "PROP",
		set = function(v)
		  inst.prop = inst.prop or { label = "PROP", logo = "" }
		  inst.prop.label = tostring(v or "")
		end
	  },
	  
	  {
	    type = "button",
	    x = 0, y = 175, w = 104, h = 32,
	    text = (TXT.SETTINGS_SAVE or "Sauver"),
        color = getOffButtonColor(),
	    press = function() saveConfig() end
	  },
    }
  }
end

local function buildRightColumn()
  return {
    type = "box",
    x = 350,
    y = 0,
    w = 108,
    h = 240,
    children = {
      { type = "label", x = 0, y = 0,  w = 100, text = TXT.SETTINGS_INSTANCE or "INSTANCE" },
      { type = "numberEdit", x = 0, y = 24, min = 1, max = 4, w = 108,
        get = function() return editor.instanceId end,
        set = function(v)
          editor.instanceId = v
          reopenPage()
        end },

      { type = "button", x = 0,  y = 62, w = 48, h = 32, text = "-", color = getOffButtonColor(), press = function() cycleInstance(-1); reopenPage() end },
      { type = "button", x = 56, y = 62, w = 48, h = 32, text = "+", color = getOffButtonColor(), press = function() cycleInstance(1); reopenPage() end },

      { type = "label", x = 0, y = 108, w = 100, text = TXT.SETTINGS_BUTTON or "BOUTON" },
      { type = "numberEdit", x = 0, y = 132, min = 1, max = 16, w = 108,
        get = function() return editor.buttonIndex end,
        set = function(v)
          editor.buttonIndex = v
          reopenPage()
        end },

      { type = "button", x = 0,  y = 170, w = 48, h = 32, text = "-", color = getOffButtonColor(), press = function() cycleButton(-1); reopenPage() end },
      { type = "button", x = 56, y = 170, w = 48, h = 32, text = "+", color = getOffButtonColor(), press = function() cycleButton(1); reopenPage() end },
    }
  }
end

local function buildCenterColumn(btn, inst)
  btn, inst = getCurrentButtonState()
  local logoPath = getLogoPath(btn.logo)

  local children = {
    { type = "label", x = 80, y = 0, w = 230, text = (TXT.SETTINGS_BUTTON or "BOUTON") .. " " .. tostring(editor.buttonIndex) },
  
    {
      type = "button",
      x = 0, y = 56, w = 86, h = 100,
      text = logoPath and "" or (TXT.SETTINGS_LOGO or "LOGO"),
      color = getOffButtonColor(),
      press = function()
        editor.logoPickerOpen = true
        reopenPage()
      end
    },
	
  }

  if logoPath then
    children[#children + 1] = {
      type = "image",
      x = 5, y = 65, w = 80, h = 80,
      file = logoPath,
      fill = false
    }
  end


  return {
    type = "box",
    x = 122,
    y = 4,
    w = 230,
    h = 230,
    children = children
  }
end

function open()
  loadTexts()

  -- IMPORTANT :
  --   On ne recharge pas le fichier modèle à chaque reopen().
  --   Sinon toute modification en mémoire (type, logo, etc.) est écrasée
  --   avant même de pouvoir être affichée ou sauvée.
  if not editor.cfg then
    loadConfig()
  else
    ensureConfig()
  end

  local btn, inst = getCurrentButtonState()

  if editor.logoPickerOpen then
    local logos = getLogoList()

    lvgl.clear()
    local page = lvgl.page({
      title = TXT.SETTINGS_LOGO or "LOGO",
      subtitle = getModelName(),
      icon = "/WIDGETS/XANYLVGL/Images/RCUL30x30.png",
      back = function()
        editor.logoPickerOpen = false
        reopenPage()
      end,
    })

    local children = {
      {
        type = "button",
        text = "(aucun)",
        w = 220,
        color = getOffButtonColor(),
        press = function()
          local inst2 = getInstance()
          inst2.buttons[editor.buttonIndex].logo = ""
          saveConfig()
          editor.logoPickerOpen = false
          reopenPage()
        end
      }
    }

    local y = 42
    for _, name in ipairs(logos) do
      local logoPath = getLogoPath(name)
      children[#children + 1] = {
        type = "box",
        x = 0,
        y = y,
        w = 250,
        h = 42,
        children = {
          {
            type = "button",
            x = 0, y = 0, w = 250, h = 38,
            text = name,
            color = getOffButtonColor(),
            press = function()
              local inst2 = getInstance()
              inst2.buttons[editor.buttonIndex].logo = name
              saveConfig()
              editor.logoPickerOpen = false
              reopenPage()
            end
          }
        }
      }
      if logoPath then
        children[#children + 1] = {
          type = "image",
          x = 8,
          y = y + 3,
          w = 28,
          h = 32,
          file = logoPath,
          fill = false
        }
      end
      y = y + 44
    end

    page:build({
      {
        type = "box",
        x = 0,
        y = 0,
        w = 260,
        h = y + 10,
        children = children
      }
    })
    return
  end

  lvgl.clear()
  local page = lvgl.page({
    title = "XANYCTL EDIT",
    subtitle = (TXT.SETTINGS_MODEL or "Modèle: ") .. getModelName(),
    icon = "/WIDGETS/XANYLVGL/Images/RCUL30x30.png",
    back = closePage,
  })

  page:build({
    {
      type = "box",
      x = 0,
      y = 0,
      w = 472,
      h = 240,
      children = {
        buildLeftColumn(btn, inst),
        buildCenterColumn(btn, inst),
        buildRightColumn(),
      }
    }
  })
end

local function init()
  loadTexts()
  loadConfig()
end

local function run(event, touchState)
  if event == EVT_EXIT_BREAK then
    if editor.logoPickerOpen then
      editor.logoPickerOpen = false
      open()
      return
    end
    closePage()
    return
  end
end

return {
  init = init,
  run = run,
  open = open,
}
