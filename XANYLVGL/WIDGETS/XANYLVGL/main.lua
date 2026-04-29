-- XANYLVGL EdgeTx LUA 
-- Copyright (C) 2026 Pierre Montet
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.

-- XANYLVGL - Widget principal
-- EdgeTX 2.11+ / TX16S (tactile)
--
-- Objectif actuel :
--   - SW8 / SW8+PROP / SW16 / SW16+PROP
--   - trame X-Any générée côté MIXES/xanytx.lua (script de mix)
--   - le widget ne fait que piloter des "GV virtuelles" packées dans GV1..GV6
--
-- PACK GVars (vrai modèle EdgeTX : GV1..GV9 max) :
--   GV1 + GV2 : mask 16 bits (boutons 1..16)
--              GV1 = partie basse (0..2047)
--              GV2 = partie haute (0..31) -> mask = GV1 + GV2*2048
--   GV3       : Repeat (0..6)  (Repeat+1 symboles identiques si besoin)
--   GV4       : MODE stored in GV4 as 0..4
--              Widget option MODE now uses CHOICE.
--              On this project/radio, CHOICE returns 1..5, so we convert it
--              back to 0..4 before storing it in GV4.
--   GV5       : CH mémo (info confort ; la vraie voie est celle où tu mixes la sortie LUA)
--   GV6       : Synchro moteurs 1 à 4
--   GV7       : PROP (0..255) (utilisé uniquement en modes +PROP / ANGLE+PROP)
--   GV8       : ANGLE (0..359°) utilisé en mode ANGLE+PROP
--
-- IMPORTANT : Index des GVars EdgeTX
-- Dans l'interface radio les variables sont nommées :
--   GV1 .. GV9
--
-- Mais dans l'API EdgeTX (model.getGlobalVariable / setGlobalVariable)
-- les index sont BASE 0 :
--
--   index 0 = GV1
--   index 1 = GV2
--   index 2 = GV3
--   index 3 = GV4
--   index 4 = GV5
--   index 5 = GV6
--   index 6 = GV7
--   index 7 = GV8
--   index 8 = GV9
--
-- Donc :
--   PROP  (GV7)  -> index 6
--   ANGLE (GV8)  -> index 7
--   SYNC  (GV6)  -> index 5
--
-- Attention : les index 17,18,19,26,31,32 utilisés dans ce widget sont
-- des "GVars virtuelles" mappées vers les vraies GVars via gv_get/gv_set.
--
-- IMPORTANT :
--   - Dans un WIDGET, EdgeTX ne fournit pas gv_get/gv_set globalement.
--     On fournit ici des wrappers compatibles via model.getGlobalVariable()/setGlobalVariable().
--   - Les accents sont en UTF-8 (é, è, à…).

local name = "XANYLVGL"
local XANYLVGL_VERSION = 1.0

-- --------------------------------------------------------------------------
-- Extract language from wgt.options.Language
-- --------------------------------------------------------------------------
local function getLanguageCode(wgt)
  local idx = (wgt.options and wgt.options.Language) or 1
  local langs = { "cn", "de", "en", "fr", "it", "sp", "ua" }
  return langs[idx] or "fr"
end

local function getFirmwareLang()
  local fw = ""
  if getGeneralSettings then
    local gs = getGeneralSettings()
    if gs and gs.language ~= nil then
      fw = gs.language
    end
  end
  return string.lower(tostring(fw or ""))
end

local function isLangCompatible(langCode)
  -- Chinese/Ukrainian are considered incompatible by default unless the
  -- firmware language string clearly looks compatible.
  local fw = getFirmwareLang()

  if langCode == "cn" then
    if string.find(fw, "cn", 1, true) ~= nil then return true end
    if string.find(fw, "zh", 1, true) ~= nil then return true end
    if string.find(fw, "chi", 1, true) ~= nil then return true end
    return false
  elseif langCode == "ua" then
    if string.find(fw, "ua", 1, true) ~= nil then return true end
    if string.find(fw, "uk", 1, true) ~= nil then return true end
    if string.find(fw, "cyr", 1, true) ~= nil then return true end
    if string.find(fw, "ukrain", 1, true) ~= nil then return true end
    return false
  end

  return true
end

local function showFirmwareLangPopup(wgt, event)
  -- popupWarning() is not reliable in widget refresh/full-screen contexts.
  -- Use the existing warning overlay instead.
end

local Languages = { "cn", "de", "en", "fr", "it", "sp", "ua" }

local TXT_DEFAULT = {
  REQUIRED_VERSION = "required",
  BAD_VERSION = "invalid config, TEMPLATE used",
  NO_LIBGUI_FOUND = "missing libGUI file",
  NO_BUTTONS_FOUND = "missing buttons.lua file",
  NO_CONFIG_FOUND = "%s not found\n%s has been added",
  BAD_FIRMWARE_LANG = "language not supported\nuse matching firmware"
}

local TXT = {}
for k, v in pairs(TXT_DEFAULT) do
  TXT[k] = v
end

local loadedLanguageCode = nil

local function loadLanguageTexts(wgt, force)
  local langCode = getLanguageCode(wgt)

  if not force and loadedLanguageCode == langCode then
    return
  end

  loadedLanguageCode = langCode

  for k, v in pairs(TXT_DEFAULT) do
    TXT[k] = v
  end

  local effectiveLangCode = langCode

  if not isLangCompatible(langCode) then
    effectiveLangCode = "en"

    if wgt then
      wgt.badFirmwareLang = true
      wgt.badFirmwareLangShown = false
    end
  else
    if wgt then
      wgt.badFirmwareLang = false
	  wgt.badFirmwareLangShown = false
    end
  end

  local path = "/WIDGETS/XANYLVGL/Langs/" .. effectiveLangCode .. "/lang.lua"
  local chunk = loadScript(path)
  if not chunk then
    return
  end

  local ok, result = pcall(chunk)
  if not ok or type(result) ~= "table" then
    return
  end

  for k, v in pairs(result) do
    if type(v) == "string" then
      TXT[k] = v
    end
  end
end



-- --------------------------------------------------------------------------
-- Copy TEMPLATE.lua -> <ModelName>.lua if missing
-- --------------------------------------------------------------------------
local function createModelConfig(modelName)
  local srcPath = "/WIDGETS/" .. name .. "/TEMPLATE.lua"
  local dstPath = "/WIDGETS/" .. name .. "/" .. modelName .. ".lua"

  local fcheck = io.open(dstPath, "r")
  if fcheck then
    io.close(fcheck)
    return true
  end

  local fsrc = io.open(srcPath, "r")
  if not fsrc then
    return false
  end

  local content = io.read(fsrc, 32768)
  io.close(fsrc)

  if not content or content == "" then
    return false
  end

  local fdst = io.open(dstPath, "w")
  if not fdst then
    return false
  end

  io.write(fdst, content)
  io.close(fdst)

  return true
end


-- --------------------------------------------------------------------------
-- Build localized "model config missing -> TEMPLATE added" warning
-- Language file may contain one line or two lines separated with \n.
-- %s is replaced by "<ModelName>.lua".
-- --------------------------------------------------------------------------
local function buildNoConfigWarning(wgt, modelName)
  loadLanguageTexts(wgt, true)

  local txt = tostring(TXT.NO_CONFIG_FOUND or "%s not found\n%s has been added")
  local modelFile = modelName .. ".lua"

  -- Accepte :
  --   - un vrai retour à la ligne
  --   - CRLF
  --   - la séquence texte "\n"
  txt = string.gsub(txt, "\r\n", "\n")
  txt = string.gsub(txt, "\r", "\n")
  txt = string.gsub(txt, "\\n", "\n")

  txt = string.gsub(txt, "%%s", modelFile, 1)
  txt = string.gsub(txt, "%%s", modelFile, 1)

  return txt
end

-- --------------------------------------------------------------------------
-- EdgeTX version check
--
-- This widget requires EdgeTX >= 2.11:
--   - CHOICE widget option type
--   - >5 options support
-- --------------------------------------------------------------------------
local ver, radio, maj, minor, rev, osname = getVersion()
local os1 = string.format("%d.%d", maj, minor)

local EDGE_MIN_OK = false
if maj > 2 then
  EDGE_MIN_OK = true
elseif maj == 2 and minor >= 11 then
  EDGE_MIN_OK = true
end

-- --------------------------------------------------------------------------
-- Multi-instance via Flight Modes (FM banks)
--
-- We keep the original "1-instance" philosophy (GV1..GV6 mapping) but we store
-- 4 independent banks in the model's Flight Modes:
--   ID=1 -> FM0, ID=2 -> FM1, ID=3 -> FM2, ID=4 -> FM3
--
-- Advantages:
--   - No SD writes
--   - Very reliable and fast
--
-- NOTE:
--   This uses model.getGlobalVariable()/setGlobalVariable() with a flight mode
--   parameter. It does NOT change your active flight mode; it only selects the
--   GV bank to read/write.
-- --------------------------------------------------------------------------
local function getFM(options)
  local id = (options and options.ID) or 1
  id = tonumber(id) or 1
  if id < 1 then id = 1 end
  if id > 4 then id = 4 end
  return id - 1 -- FM0..FM3
end

-- --------------------------------------------------------------------------
-- Runtime context used by gv_get/gv_set
--
-- gv_get()/gv_set() are called by buttons.lua through the API table and do not
-- receive the widget instance directly. We therefore keep the "current options"
-- here so the correct FM bank is always used.
-- --------------------------------------------------------------------------
local currentOptions = nil

-- --------------------------------------------------------------------------
-- Temporary warning overlay
--
-- If the model-specific config file is missing or invalid, we fall back to
-- TEMPLATE.lua and show a centered red warning with dark grey shadow for 3s.
-- --------------------------------------------------------------------------
local warningText = nil
local warningUntil = 0
local warningOwnerKey = nil

-- --------------------------------------------------------------------------
-- normalizeModeChoice()
--
-- MODE comes back as 1..5 with CHOICE in this project/radio:
--   1 = SW8
--   2 = SW8+PROP
--   3 = SW16
--   4 = SW16+PROP
--   5 = ANGLE+PROP

-- The X-Any encoder always expects 0..4 stored in GV4:
--   0 = SW8
--   1 = SW8+PROP
--   2 = SW16
--   3 = SW16+PROP
--   4 = ANGLE+PROP
-- --------------------------------------------------------------------------
local function normalizeModeChoice(v)
  v = tonumber(v) or 1
  if v < 1 then v = 1 end
  if v > 5 then v = 5 end
  return v - 1
end

local function getWarningOwnerKey(wgt)
  local id = ((wgt and wgt.options) and wgt.options.ID) or 1
  local x = ((wgt and wgt.zone) and wgt.zone.x) or 0
  local y = ((wgt and wgt.zone) and wgt.zone.y) or 0
  return tostring(id) .. ":" .. tostring(x) .. ":" .. tostring(y)
end

-- --------------------------------------------------------------------------
-- deepCopy()
-- Used so each widget instance gets its own config table.
-- This avoids accidental sharing between widgets.
-- --------------------------------------------------------------------------
local function deepCopy(src)
  if type(src) ~= "table" then
    return src
  end

  local dst = {}
  for k, v in pairs(src) do
    dst[k] = deepCopy(v)
  end
  return dst
end

-- --------------------------------------------------------------------------
-- selectInstanceConfig()
--
-- Supports:
--   - old 1-instance format
--   - new 4-instance format with cfg.instances[1..4]
--
-- Returns a deep copy so each widget has its own independent labels/config.
-- --------------------------------------------------------------------------
local function selectInstanceConfig(cfg, options)
  if type(cfg) ~= "table" then
    return nil
  end

  local id = (options and options.ID) or 1
  id = tonumber(id) or 1
  if id < 1 then id = 1 end
  if id > 4 then id = 4 end

  local inst = nil

  if type(cfg.instances) == "table" and type(cfg.instances[id]) == "table" then
    inst = deepCopy(cfg.instances[id])
  else
    inst = deepCopy(cfg)
  end

  if type(inst) ~= "table" then
    return nil
  end

  if type(inst.title) ~= "string" or inst.title == "" then
    inst.title = "INSTANCE " .. tostring(id)
  end

  return inst
end

-- --------------------------------------------------------------------------
-- Chargement config par modèle (fichier à côté du widget)
--
-- Priorité :
--   1) /WIDGETS/XANYLVGL/<NomDuModele>.lua
--   2) /WIDGETS/XANYLVGL/TEMPLATE.lua
--
-- Si le fichier modèle n'existe pas ou est invalide, TEMPLATE.lua est chargé
-- et un message d'avertissement temporaire est affiché.
--
-- Nouveau format 4 instances supporté :
--
--   return {
--     instances = {
--       [1] = { buttons = {...}, prop = {...} },
--       [2] = { buttons = {...}, prop = {...} },
--       [3] = { buttons = {...}, prop = {...} },
--       [4] = { buttons = {...}, prop = {...} },
--     }
--   }
--
-- Ancien format 1-instance toujours accepté :
--
--   return {
--     buttons = {...},
--     prop = {...}
--   }
-- --------------------------------------------------------------------------
local function loadModelConfig()
  local mi = model.getInfo()
  local modelName = mi.name

  local try = {
    "/WIDGETS/"..name.."/"..modelName..".lua",
    "/WIDGETS/"..name.."/TEMPLATE.lua",
  }

  local usedTemplate = false
  local cfg = nil

  --------------------------------------------------------------------------
  -- Try model file first, then TEMPLATE.lua
  --------------------------------------------------------------------------
  for i, p in ipairs(try) do
    local chunk = loadScript(p)
    if chunk then
      local ok, loaded = pcall(chunk)

      if ok and type(loaded) == "table" then
        cfg = loaded
      elseif ok and type(loaded) == "function" then
        local ok2, loaded2 = pcall(loaded)
        if ok2 and type(loaded2) == "table" then
          cfg = loaded2
        end
      end

      if cfg then
        if i == 2 and warningText == nil then
          warningText = buildNoConfigWarning({ options = currentOptions }, modelName)
          warningUntil = getTime() + 500 -- 5 seconds (tick = 10 ms)
          warningOwnerKey = getWarningOwnerKey({ options = currentOptions, zone = zone })
        end
        break
      end

      -- If the model file exists but is invalid, try TEMPLATE and report it.
      if i == 1 then
        usedTemplate = true
      end
    else
      -- Model file not found -> create it from TEMPLATE.lua, then try TEMPLATE next.
      if i == 1 then
        usedTemplate = true
        createModelConfig(modelName)
      end
    end
  end

  if usedTemplate and warningText == nil and cfg == nil then
    warningText = buildNoConfigWarning({ options = currentOptions }, modelName)
    warningUntil = getTime() + 500 -- 5 seconds (tick = 10 ms)
    warningOwnerKey = getWarningOwnerKey({ options = currentOptions, zone = zone })
  end

  if type(cfg) == "table" then
    return cfg
  end

  --------------------------------------------------------------------------
  -- Built-in safe default (used only if no external file could be loaded)
  --------------------------------------------------------------------------
  local id = (currentOptions and currentOptions.ID) or 1
  id = tonumber(id) or 1
  if id < 1 then id = 1 end
  if id > 4 then id = 4 end

  local fallback = { buttons = {} }
  for i=1,16 do
    fallback.buttons[i] = { label=tostring(i), type="toggle" }
  end
  fallback.title = "INSTANCE " .. tostring(id)
  fallback.prop = { label="PROP" }
  return fallback
end

-- --------------------------------------------------------------------------
-- Accès GVars (GV1..GV9) - API EdgeTX : index 0..8 + phase (0)
-- --------------------------------------------------------------------------
local function _getGVar(n, options)
  local fm = getFM(options)
  -- model.getGlobalVariable(gvIndex, flightMode)
  local ok, v = pcall(function() return model.getGlobalVariable(n, fm) end)
  if ok and v ~= nil then return v end
  return nil
end

local function _setGVar(n, v, options)
  local fm = getFM(options)
  v = v or 0
  pcall(function() model.setGlobalVariable(n, fm, v) end)
end

local function _getMask16()
  -- GV1 est une GVar "signée" souvent limitée à [-1024..1024].
  -- Pour stocker 11 bits (0..2047) sans perdre des bits, on stocke dans GV1 un
  -- encodage biaisé : GV1 = lo - 1024  (donc [-1024..1023]).
  local lo_enc = _getGVar(0, currentOptions) or 0
  local lo = lo_enc + 1024
  if lo < 0 then lo = 0 end
  if lo > 2047 then lo = 2047 end

  local hi = _getGVar(1, currentOptions) or 0
  if hi < 0 then hi = 0 end
  if hi > 31 then hi = 31 end

  return lo + hi * 2048
end

local function _setMask16(mask)
  -- Stockage biaisé du bas 11 bits dans GV1 :
  --   lo = mask % 2048 (0..2047)
  --   GV1 = lo - 1024 ([-1024..1023])  -> évite le "clamp" EdgeTX à 1024
  local lo = mask % 2048
  local hi = math.floor(mask / 2048) % 32
  local lo_enc = lo - 1024
  _setGVar(0, lo_enc, currentOptions)
  _setGVar(1, hi, currentOptions)
end

-- gv_get / gv_set : “GV virtuelles” utilisées par l’UI et par xanytx.lua
--   idx 1..16 -> boutons (bits)
--   idx 17    -> PROP
--   idx 18    -> Repeat
--   idx 31    -> CH mémo
--   idx 32    -> MODE
--   idx 26    -> Synchro moteurs
function gv_get(idx, default)
  if idx >= 1 and idx <= 16 then
    local mask = _getMask16()
    local bit = 2^(idx-1)
    return (math.floor(mask / bit) % 2) ~= 0 and 1 or 0
  end
  if idx == 17 then return _getGVar(6, currentOptions) or (default or 0) end
  if idx == 18 then return _getGVar(2, currentOptions) or (default or 0) end
  if idx == 19 then return _getGVar(7, currentOptions) or (default or 0) end
  if idx == 31 then return _getGVar(4, currentOptions) or (default or 0) end
  if idx == 32 then return _getGVar(3, currentOptions) or (default or 0) end
  if idx == 26 then
    local ok, v = pcall(function() return model.getGlobalVariable(5, 0) end) -- vraie GV6 en FM0
    if ok and v ~= nil then return v end
    return default or 0
  end
  return default or 0
end

function gv_set(idx, val)
  val = val or 0
  if idx >= 1 and idx <= 16 then
    local mask = _getMask16()
    local bit = 2^(idx-1)
    if val ~= 0 then
      if (math.floor(mask / bit) % 2) == 0 then mask = mask + bit end
    else
      if (math.floor(mask / bit) % 2) == 1 then mask = mask - bit end
    end
    _setMask16(mask)
    return true
  end
  if idx == 17 then _setGVar(6, val, currentOptions); return true end
  if idx == 18 then _setGVar(2, val, currentOptions); return true end
  if idx == 19 then _setGVar(7, val, currentOptions); return true end
  if idx == 31 then _setGVar(4, val, currentOptions); return true end
  if idx == 32 then _setGVar(3, val, currentOptions); return true end
  if idx == 26 then
    local ok = pcall(function() model.setGlobalVariable(5, 0, val or 0) end) -- vraie GV6 en FM0
    if not ok then
      model.setGlobalVariable(5, val or 0)
    end
    return true
  end
  return false
end

-- --------------------------------------------------------------------------
-- API passée à buttons.lua (évite les globals et clarifie)
-- --------------------------------------------------------------------------
local function makeAPI(optionsProvider)
  -- IMPORTANT :
  --   Cette API ne dépend plus du global mutable currentOptions.
  --   Chaque widget lit/écrit maintenant directement dans SA banque FM
  --   via les options de SON instance.
  --
  --   Cela évite qu'un cadran ou un slider d'une instance #2/#3/#4
  --   écrive par erreur dans la banque d'une autre instance quand plusieurs
  --   widgets sont visibles/rafraîchis sur le même écran.

  local function getOptions()
    if type(optionsProvider) == "function" then
      return optionsProvider() or currentOptions
    end
    return currentOptions
  end

  local function getMask16For(opts)
    local lo_enc = _getGVar(0, opts) or 0
    local lo = lo_enc + 1024
    if lo < 0 then lo = 0 end
    if lo > 2047 then lo = 2047 end

    local hi = _getGVar(1, opts) or 0
    if hi < 0 then hi = 0 end
    if hi > 31 then hi = 31 end

    return lo + hi * 2048
  end

  local function setMask16For(mask, opts)
    local lo = mask % 2048
    local hi = math.floor(mask / 2048) % 32
    local lo_enc = lo - 1024
    _setGVar(0, lo_enc, opts)
    _setGVar(1, hi, opts)
  end

  local function api_gv_get(idx, default)
    local opts = getOptions()

    if idx >= 1 and idx <= 16 then
      local mask = getMask16For(opts)
      local bit = 2^(idx-1)
      return (math.floor(mask / bit) % 2) ~= 0 and 1 or 0
    end

    if idx == 17 then return _getGVar(6, opts) or (default or 0) end
    if idx == 18 then return _getGVar(2, opts) or (default or 0) end
    if idx == 19 then return _getGVar(7, opts) or (default or 0) end
    if idx == 31 then return _getGVar(4, opts) or (default or 0) end
    if idx == 32 then return _getGVar(3, opts) or (default or 0) end

    if idx == 26 then
      local ok, v = pcall(function() return model.getGlobalVariable(5, 0) end) -- vraie GV6 en FM0
      if ok and v ~= nil then return v end
      return default or 0
    end

    return default or 0
  end

  local function api_gv_set(idx, val)
    local opts = getOptions()
    val = val or 0

    if idx >= 1 and idx <= 16 then
      local mask = getMask16For(opts)
      local bit = 2^(idx-1)
      if val ~= 0 then
        if (math.floor(mask / bit) % 2) == 0 then mask = mask + bit end
      else
        if (math.floor(mask / bit) % 2) == 1 then mask = mask - bit end
      end
      setMask16For(mask, opts)
      return true
    end

    if idx == 17 then _setGVar(6, val, opts); return true end
    if idx == 18 then _setGVar(2, val, opts); return true end
    if idx == 19 then _setGVar(7, val, opts); return true end
    if idx == 31 then _setGVar(4, val, opts); return true end
    if idx == 32 then _setGVar(3, val, opts); return true end

    if idx == 26 then
      local ok = pcall(function() model.setGlobalVariable(5, 0, val or 0) end) -- vraie GV6 en FM0
      if not ok then
        model.setGlobalVariable(5, val or 0)
      end
      return true
    end

    return false
  end

  return {
    gv_get = api_gv_get,
    gv_set = api_gv_set,
	VERSION = XANYLVGL_VERSION,
  }
end

-- --------------------------------------------------------------------------
-- Options widget (EdgeTX)
-- --------------------------------------------------------------------------
local options = {
  { "ID",     VALUE, 1, 1, 4 },                                        -- Instance ID (1..4) mapped to FM0..FM3
  { "MODE",   CHOICE, 1, { "SW8", "SW8+PROP", "SW16", "SW16+PROP", "ANGLE+PROP" } }, -- CHOICE returns 1..5 here
  { "CH",     VALUE, 5, 1, 16 },                                       -- voie (info + confort)
  { "Repeat", VALUE, 0, 0, 6 },                                        -- Repeat (0 = pas de répétition)
  { "OffCol", COLOR, DARKGREEN },                                      -- Couleur OFF
  { "OnCol",  COLOR, GREEN },                                          -- Couleur ON
  { "Shadow", BOOL, 0 },                                               -- Ombres
  { "Synchro", BOOL, 0 },
  { "Language", CHOICE, 4, Languages },     -- Languages fr par défaut
  
}



-- --------------------------------------------------------------------------
-- applyMotorSync()
--
-- ID1 (FM0) is the master for ANGLE / PROP.
--
-- GV6 (true GV6 in FM0) is used as a sync mask:
--   bit0 = sync ID2 (FM1)
--   bit1 = sync ID3 (FM2)
--   bit2 = sync ID4 (FM3)
--
-- Only ANGLE / PROP are copied.
-- Other values remain independent.
-- --------------------------------------------------------------------------
local function applyMotorSync()
  -- IMPORTANT :
  --   La synchro réelle ANGLE/PROP est gérée côté bouton SYNCHRO
  --   et côté xanytx_common.lua.
  --   Ici on NE COPIE PLUS les valeurs GV7/GV8 de FM0 vers FM1..FM3.
  --   Sinon les moteurs restent liés même quand le bouton SYNCHRO est sur OFF.
  --
  --   Conséquence voulue :
  --     - SYNCHRO OFF  -> chaque moteur reste totalement indépendant
  --     - SYNCHRO ON   -> le mix utilise les valeurs du maître sans écraser
  --                       les GVars locales des autres instances
  --
  -- volontairement vide
end

-- --------------------------------------------------------------------------
-- drawVersionError()
-- If EdgeTX is older than 2.11, the widget is blocked cleanly and displays
-- a blinking red / dark-grey warning.
-- --------------------------------------------------------------------------
local function drawVersionError(wgt)
  local x = wgt.zone.x + math.floor(wgt.zone.w / 2)
  local y = wgt.zone.y + math.floor(wgt.zone.h / 2) - 10

  local blink = math.floor(getTime() / 25) % 2

  local msg = "EdgeTX " .. os1 .. "+ - " .. tostring(TXT.REQUIRED_VERSION or "required")

  if blink == 0 then
    lcd.setColor(CUSTOM_COLOR, DARKGREY)
    lcd.drawText(x + 2, y + 2, msg, CUSTOM_COLOR + CENTER + MIDSIZE)

    lcd.setColor(CUSTOM_COLOR, RED)
    lcd.drawText(x, y, msg, CUSTOM_COLOR + CENTER + MIDSIZE)
  else
    lcd.setColor(CUSTOM_COLOR, RED)
    lcd.drawText(x + 2, y + 2, msg, CUSTOM_COLOR + CENTER + MIDSIZE)

    lcd.setColor(CUSTOM_COLOR, DARKGREY)
    lcd.drawText(x, y, msg, CUSTOM_COLOR + CENTER + MIDSIZE)
  end
end

-- --------------------------------------------------------------------------
-- create() : charge config modèle + UI
-- --------------------------------------------------------------------------
local function create(zone, opts)
  local wgt = {
    zone = zone,
    options = opts,
  }

  -- Runtime context used by gv_get/gv_set
  currentOptions = opts
  wgt.badFirmwareLang = false
  
  loadLanguageTexts(wgt, true)

  -- Block widget cleanly if EdgeTX version is too old
  if not EDGE_MIN_OK then
    wgt.versionError = true
    return wgt
  end

  -- Charge la configuration modèle (ou TEMPLATE.lua en fallback)
  local rawCfg = loadModelConfig()
  wgt.config = selectInstanceConfig(rawCfg, opts)

  -- Synchronise MODE / CH / Repeat vers les GVars packées
  local mode = normalizeModeChoice((wgt.options and wgt.options.MODE) or 1)
  local ch   = (wgt.options and wgt.options.CH) or 5
  local rep  = (wgt.options and wgt.options.Repeat) or 0
  gv_set(32, mode)
  gv_set(31, ch)
  gv_set(18, rep)

  -- UI libGUI dans fichier séparé
  local uiChunk = loadScript("/WIDGETS/"..name.."/buttons.lua")
  if uiChunk then
    wgt.ui = uiChunk(zone, opts, wgt.config, makeAPI(function() return wgt.options end))
  else
    wgt.ui = nil
  end

  if lvgl and wgt.ui and wgt.ui.build then
    lvgl.clear()
    wgt.ui:build()
  end

  return wgt
end

-- --------------------------------------------------------------------------
-- update() : appelé quand l’utilisateur modifie les options
-- --------------------------------------------------------------------------
local function update(wgt, opts)
  local oldId = (wgt.options and wgt.options.ID) or 1

  wgt.options = opts
  currentOptions = opts
  wgt.badFirmwareLangShown = false
  
  loadLanguageTexts(wgt, true)

  -- If version is too old, keep the widget blocked.
  if wgt.versionError then
    return
  end

  -- Synchronise MODE / CH / Repeat vers les GVars packées
  local mode = normalizeModeChoice((wgt.options and wgt.options.MODE) or 1)
  local ch   = (wgt.options and wgt.options.CH) or 5
  local rep  = (wgt.options and wgt.options.Repeat) or 0
  gv_set(32, mode)
  gv_set(31, ch)
  gv_set(18, rep)

  -- If ID changed, reload config + rebuild UI so labels update immediately
  if oldId ~= ((opts and opts.ID) or 1) then
    local rawCfg = loadModelConfig()
    wgt.config = selectInstanceConfig(rawCfg, opts)

    local uiChunk = loadScript("/WIDGETS/"..name.."/buttons.lua")
    if uiChunk then
      wgt.ui = uiChunk(wgt.zone, opts, wgt.config, makeAPI(function() return wgt.options end))
    else
      wgt.ui = nil
    end
    if lvgl and wgt.ui and wgt.ui.build then
      lvgl.clear()
      wgt.ui:build()
    end
    return
  end

  if wgt.ui and wgt.ui.update then
    wgt.ui.options = opts
    wgt.ui.config = wgt.config
    wgt.ui:update()
  end

  if lvgl and wgt.ui and wgt.ui.build then
    lvgl.clear()
    wgt.ui:build()
  end
end

-- --------------------------------------------------------------------------
-- drawWarning()
-- Centered temporary warning text:
--   - dark grey shadow
--   - red foreground
-- --------------------------------------------------------------------------


local function drawWarning(wgt)
  if not warningText then return false end
  if getTime() >= warningUntil then
    warningText = nil
    warningOwnerKey = nil
    return false
  end

  if warningOwnerKey and getWarningOwnerKey(wgt) ~= warningOwnerKey then
    return false
  end

  local x = wgt.zone.x + math.floor(wgt.zone.w / 2)
  local y = wgt.zone.y + math.floor(wgt.zone.h / 2) - 20

  local txt = tostring(warningText)
  local pos = string.find(txt, string.char(10), 1, true)

  local l1 = txt
  local l2 = nil

  if pos then
    l1 = string.sub(txt, 1, pos - 1)
    l2 = string.sub(txt, pos + 1)
  end

  lcd.setColor(CUSTOM_COLOR, DARKGREY)
  lcd.drawText(x + 2, y + 2, l1, CUSTOM_COLOR + CENTER + MIDSIZE)

  lcd.setColor(CUSTOM_COLOR, RED)
  lcd.drawText(x, y, l1, CUSTOM_COLOR + CENTER + MIDSIZE)

  if l2 and l2 ~= "" then
    lcd.setColor(CUSTOM_COLOR, DARKGREY)
    lcd.drawText(x + 2, y + 42, l2, CUSTOM_COLOR + CENTER + MIDSIZE)

    lcd.setColor(CUSTOM_COLOR, RED)
    lcd.drawText(x, y + 40, l2, CUSTOM_COLOR + CENTER + MIDSIZE)
  end

  return true
end



-- --------------------------------------------------------------------------
-- refresh() : dessin + évènements
-- --------------------------------------------------------------------------
local function refresh(wgt, event, touchState)
  currentOptions = wgt.options
  
  if wgt.badFirmwareLang and not wgt.badFirmwareLangShown then
    warningText = tostring(TXT.BAD_FIRMWARE_LANG or "language not supported\nuse matching firmware")
    warningUntil = getTime() + 500 -- 5 seconds
    warningOwnerKey =
      tostring(((wgt and wgt.options) and wgt.options.ID) or 1) .. ":" ..
      tostring(((wgt and wgt.zone) and wgt.zone.x) or 0) .. ":" ..
      tostring(((wgt and wgt.zone) and wgt.zone.y) or 0)

    wgt.badFirmwareLangShown = true
  end
  
  if wgt.versionError then
    drawVersionError(wgt)
    return
  end

  applyMotorSync()

  -- Warning overlay displayed for 3 seconds, then normal widget display resumes.
  if drawWarning(wgt) then
    return
  end

  if lvgl and wgt.ui and wgt.ui.handleEvent then
    wgt.ui:handleEvent(event, touchState)
  end

  if wgt.ui and wgt.ui.refresh then
    wgt.ui:refresh(event, touchState)
  else
    -- fallback minimal si buttons.lua absent
	local msg = tostring(TXT.NO_BUTTONS_FOUND or "XANYLVGL buttons.lua missing")
	lcd.drawText(wgt.zone.x+2, wgt.zone.y+2, msg, SMLSIZE)
  end
end

local function background(wgt)
  currentOptions = wgt.options
  applyMotorSync()
  if wgt.versionError then
    return
  end
  if wgt.ui and wgt.ui.background then
    wgt.ui:background()
  end
end

return {
  name = name,
  create = create,
  refresh = refresh,
  background = background,
  options = options,
  update = update,
  useLvgl = true
}
