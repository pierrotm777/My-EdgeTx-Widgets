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

-- XANYLVGL - LVGL Lib (boutons + slider PROP)
-- Ce fichier ne contient que l'interface graphique et les interactions tactiles.
-- Il reçoit :
--   zone, options, config, api
-- et renvoie un objet widget avec méthodes refresh/update/background.
--
-- IMPORTANT :
--   - On dessine toujours dans zone (pas de coordonnées 480x272 "en dur").
--   - On ne bloque pas le bouton RET : on ne consomme pas EVT_EXIT_BREAK.

local zone, options, config, api = ...
local widget = {}
widget.options = options
widget.config = config or {}
widget.api = api or {}
-- IMPORTANT :
-- L'option widget "Synchro" ne sert qu'à afficher le bouton SYNCHRO
-- sur l'instance #1. Elle ne doit jamais activer la synchro à elle seule.
-- Au démarrage, la synchro réelle est donc toujours à OFF.
widget.syncButtonState = 0
widget.settingsScreenOpen = false
widget.handleEvent = nil

local SETTINGS_HOT_X_PAD = 78
local SETTINGS_HOT_Y = 0
local SETTINGS_HOT_W = 74
local SETTINGS_HOT_H = 28

local settingsScreen = nil
local settingsScreenInitDone = false

-- Déclarations anticipées :
-- ces fonctions sont utilisées avant leur définition complète plus bas.
local openSettingsPage
local closeSettingsPage

_G.XANYCTL_SETTINGS_CONTEXT = _G.XANYCTL_SETTINGS_CONTEXT or {}

local function publishSettingsContext()
  local ctx = _G.XANYCTL_SETTINGS_CONTEXT
  ctx.zone = zone
  ctx.options = widget.options
  ctx.config = widget.config
  ctx.api = widget.api
  ctx.widget = widget
  ctx.closeSettings = closeSettingsPage
  return ctx
end


local function isInSettingsHotZone(x, y)
  local hx = zone.x + zone.w - SETTINGS_HOT_X_PAD
  local hy = zone.y + SETTINGS_HOT_Y
  return x >= hx and x < (hx + SETTINGS_HOT_W) and y >= hy and y < (hy + SETTINGS_HOT_H)
end

local function loadSettingsScreen()
  if settingsScreen ~= nil then
    return settingsScreen
  end

  publishSettingsContext()
  local chunk = loadScript("/WIDGETS/XANYLVGL/settings.lua")
  if not chunk then
    settingsScreen = false
    return settingsScreen
  end

  local ok, screen = pcall(chunk)
  if ok then
    settingsScreen = screen or false
  else
    settingsScreen = false
  end
  return settingsScreen
end

local function handleSettingsHotZone(event, touchState)
  if event == EVT_TOUCH_FIRST and touchState then
    if isInSettingsHotZone(touchState.x, touchState.y) then
      if widget.settingsScreenOpen then
        closeSettingsPage()
      else
        openSettingsPage()
      end
      return true
    end
  end

  return false
end

openSettingsPage = function()
  publishSettingsContext()
  local scr = loadSettingsScreen()
  if not scr then
    return false
  end

  -- IMPORTANT :
  --   Sur best22, le 1er appui ouvrait parfois une page vide puis le 2e
  --   affichait réellement settings. On initialise donc toujours l'écran
  --   avant l'ouverture réelle, puis on efface la vue courante juste avant
  --   de construire la page settings.
  if (not settingsScreenInitDone) and type(scr.init) == "function" then
    pcall(scr.init)
    settingsScreenInitDone = true
  end

  if lvgl and type(lvgl.clear) == "function" then
    lvgl.clear()
  end

  if type(scr.open) == "function" then
    local ok = pcall(scr.open)
    if ok then
      widget.settingsScreenOpen = true
      return true
    end
    widget.settingsScreenOpen = false
    return false
  end

  widget.settingsScreenOpen = true
  return true
end

closeSettingsPage = function()
  widget.settingsScreenOpen = false
  settingsScreenInitDone = false

  -- IMPORTANT :
  --   Ne pas reconstruire le widget ici pendant qu'une page LVGL est encore
  --   active, sinon on sort sur une page vide et le cycle RETURN peut devenir
  --   instable dans le simu.
  currentLayoutKey = nil

  if lvgl and type(lvgl.clear) == "function" then
    lvgl.clear()
  end
end

_G.XANYCTL_widgetPresence = _G.XANYCTL_widgetPresence or {}
local sharedWidgetPresence = _G.XANYCTL_widgetPresence
_G.XANYCTL_widgetPresenceSeen = _G.XANYCTL_widgetPresenceSeen or {}
local sharedWidgetPresenceSeen = _G.XANYCTL_widgetPresenceSeen
_G.XANYCTL_widgetAnglePropPresence = _G.XANYCTL_widgetAnglePropPresence or {}
local sharedWidgetAnglePropPresence = _G.XANYCTL_widgetAnglePropPresence
_G.XANYCTL_syncMaskShared = _G.XANYCTL_syncMaskShared or 0
local sharedSyncMask = _G.XANYCTL_syncMaskShared

local function markWidgetPresent(id, isAnglePropMode)
  id = tonumber(id) or 1
  if id < 1 then id = 1 end
  if id > 4 then id = 4 end
  sharedWidgetPresence[id] = getTime()
  sharedWidgetPresenceSeen[id] = true
  -- Mémorise aussi si cette instance est réellement en mode ANGLE+PROP.
  -- La synchro moteur ne concerne que ce mode.
  sharedWidgetAnglePropPresence[id] = (isAnglePropMode == true)
end

local function isWidgetPresent(id)
  if id == 1 then
    return true
  end

  if sharedWidgetPresenceSeen[id] then
    return true
  end

  local t = sharedWidgetPresence[id]
  if not t then
    return false
  end

  return true
end

local function isAnglePropWidgetPresent(id)
  if id == 1 then
    return true
  end

  return sharedWidgetAnglePropPresence[id] == true
end

-- --------------------------------------------------------------------------
-- normalizeModeChoice()
--
-- Le widget option MODE peut revenir en 1..4 avec CHOICE :
--   1 = SW8
--   2 = SW8+PROP
--   3 = SW16
--   4 = SW16+PROP
--
-- Toute l'UI interne attend 0..3 :
--   0 = SW8
--   1 = SW8+PROP
--   2 = SW16
--   3 = SW16+PROP
-- --------------------------------------------------------------------------
local function normalizeModeChoice(mode)
  mode = tonumber(mode) or 0

  if mode >= 1 and mode <= 5 then
    return mode - 1
  end

  if mode >= 0 and mode <= 4 then
    return mode
  end

  return 0
end

-- --------------------------------------------------------------------------
-- Accès locaux directs à PROP / ANGLE pour l'instance courante
-- --------------------------------------------------------------------------
local function getWidgetFMIndex()
  local id = (widget.options and widget.options.ID) or 1
  id = tonumber(id) or 1
  if id < 1 then id = 1 end
  if id > 4 then id = 4 end
  return id - 1
end

local function getLocalPropValue()
  local fm = getWidgetFMIndex()
  local ok, v = pcall(function() return model.getGlobalVariable(6, fm) end) -- vraie GV7
  if ok and v ~= nil then
    v = math.floor(tonumber(v) or 0)
    if v < 0 then v = 0 end
    if v > 255 then v = 255 end
    return v
  end
  return 0
end

local function setLocalPropValue(v)
  local fm = getWidgetFMIndex()
  v = math.floor(tonumber(v) or 0)
  if v < 0 then v = 0 end
  if v > 255 then v = 255 end
  pcall(function() model.setGlobalVariable(6, fm, v) end) -- vraie GV7
end

local function getLocalAngleValue()
  local fm = getWidgetFMIndex()
  local ok, v = pcall(function() return model.getGlobalVariable(7, fm) end) -- vraie GV8
  if ok and v ~= nil then
    v = math.floor(tonumber(v) or 0)
    while v < 0 do v = v + 360 end
    while v >= 360 do v = v - 360 end
    return v
  end
  return 0
end

local function setLocalAngleValue(v)
  local fm = getWidgetFMIndex()
  v = math.floor((tonumber(v) or 0) + 0.5)
  while v < 0 do v = v + 360 end
  while v >= 360 do v = v - 360 end
  pcall(function() model.setGlobalVariable(7, fm, v) end) -- vraie GV8
end

-- --------------------------------------------------------------------------
-- Lecture locale par pod (ID1..ID4)
--
-- IMPORTANT :
--   drawPods() doit pouvoir afficher les valeurs de chaque pod séparément.
--   Si on relit seulement PROP/ANGLE du widget courant puis qu'on les réutilise
--   pour dessiner les 4 pods, l'affichage donne l'impression d'une synchro
--   permanente même quand les sorties sont indépendantes.
-- --------------------------------------------------------------------------
local function getPropValueForPod(id)
  id = tonumber(id) or 1
  if id < 1 then id = 1 end
  if id > 4 then id = 4 end

  local fm = id - 1
  local ok, v = pcall(function() return model.getGlobalVariable(6, fm) end) -- vraie GV7
  if ok and v ~= nil then
    v = math.floor(tonumber(v) or 0)
    if v < 0 then v = 0 end
    if v > 255 then v = 255 end
    return v
  end
  return 0
end

local function getAngleValueForPod(id)
  id = tonumber(id) or 1
  if id < 1 then id = 1 end
  if id > 4 then id = 4 end

  local fm = id - 1
  local ok, v = pcall(function() return model.getGlobalVariable(7, fm) end) -- vraie GV8
  if ok and v ~= nil then
    v = math.floor(tonumber(v) or 0)
    while v < 0 do v = v + 360 end
    while v >= 360 do v = v - 360 end
    return v
  end
  return 0
end

-- --------------------------------------------------------------------------
-- Déclaration anticipée : getSyncMask()
--
-- IMPORTANT :
--   isCurrentPodSyncedSlave() utilise getSyncMask() avant sa définition
--   historique plus bas dans le fichier.
--   En Lua, sans déclaration anticipée, l'appel voit nil et le widget plante
--   à l'ouverture de certaines instances.
-- --------------------------------------------------------------------------
local getSyncMask

local function isCurrentPodSyncedSlave()
  local id = (widget.options and widget.options.ID) or 1
  id = tonumber(id) or 1
  if id <= 1 then
    return false
  end

  local mode = normalizeModeChoice((widget.options and widget.options.MODE) or 0)
  if mode ~= 4 then
    return false
  end

  local mask = getSyncMask()
  local bit = 2 ^ (id - 2) -- POD2->bit0, POD3->bit1, POD4->bit2
  return (math.floor(mask / bit) % 2) ~= 0
end



-- --------------------------------------------------------------------------
-- Couleurs personnalisables (options du widget)
--   OffCol / OnCol : index 0..7 dans une petite palette basée sur COLOR_THEME_*
-- IMPORTANT:
--   - On reste sur les couleurs "theme" EdgeTX pour garder une bonne lisibilité.
--   - Si une option n'est pas disponible (ancien modèle), on retombe sur les couleurs par défaut.
-- --------------------------------------------------------------------------

-- --------------------------------------------------------------------------
-- Couleurs configurables depuis les options du widget
-- --------------------------------------------------------------------------
-- --------------------------------------------------------------------------
-- Ombres (optionnelles)
-- --------------------------------------------------------------------------
local function isShadowEnabled()
  -- BOOL option : true/false (selon EdgeTX)
  return widget.options and widget.options.Shadow
end

local function getOffOnColors()
  local offCol = (widget.options and widget.options.OffCol) or COLOR_THEME_SECONDARY1
  local onCol  = (widget.options and widget.options.OnCol)  or COLOR_THEME_PRIMARY2
  return offCol, onCol
end

local libGUI_chunk
local libGUI
local gui
local logoBitmap = false
local logoBitmapCompact = false
local synchroBitmap = false

-- --------------------------------------------------------------------------
-- Logos par bouton définis dans le fichier modèle/TEMPLATE.lua
--   buttons[i].logo = "MonLogo.png"
-- ou buttons[i].logo = "/WIDGETS/XANYLVGL/Images/MonLogo.png"
--
-- Les logos sont mis en cache pour éviter les rechargements.
-- --------------------------------------------------------------------------
local buttonLogoBitmaps = {}

-- --------------------------------------------------------------------------
-- Helper: récupère largeur/hauteur bitmap si possible (selon implémentation EdgeTX)
-- --------------------------------------------------------------------------
local function getBitmapSizeSafe(bmp)
  if not bmp then return nil, nil end

  -- IMPORTANT :
  -- certains bitmaps EdgeTX sont des userdata.
  -- Il ne faut pas accéder directement à bmp.w / bmp.h,
  -- sinon certaines versions plantent avec "attempt to index a userdata value".

  local bmpType = type(bmp)

  -- cas table avec champs
  if bmpType == "table" then
    if bmp.w and bmp.h then
      return bmp.w, bmp.h
    end
    if type(bmp.getSize) == "function" then
      local ok, w, h = pcall(bmp.getSize, bmp)
      if ok then return w, h end
    end
    if type(bmp.width) == "function" and type(bmp.height) == "function" then
      local ok, w = pcall(bmp.width, bmp)
      local ok2, h = pcall(bmp.height, bmp)
      if ok and ok2 then return w, h end
    end
  end

  -- userdata : on tente uniquement des appels protégés si des méthodes existent
  if bmpType == "userdata" then
    local okType, getSizeType = pcall(function() return type(bmp.getSize) end)
    if okType and getSizeType == "function" then
      local ok, w, h = pcall(function() return bmp:getSize() end)
      if ok then return w, h end
    end

    local okTypeW, widthType = pcall(function() return type(bmp.width) end)
    local okTypeH, heightType = pcall(function() return type(bmp.height) end)
    if okTypeW and okTypeH and widthType == "function" and heightType == "function" then
      local ok, w = pcall(function() return bmp:width() end)
      local ok2, h = pcall(function() return bmp:height() end)
      if ok and ok2 then return w, h end
    end
  end

  return nil, nil
end


-- --------------------------------------------------------------------------
-- Réglages d'affichage des logos de boutons
--   Les bitmaps sont stockés dans un seul dossier : /WIDGETS/XANYLVGL/Logos8/
--   En mode 16 boutons, on utilise le même logo avec un scale réduit.
--
--   8 boutons  : logos source ~75x75, scale 100%
--   16 boutons : mêmes logos, scale 50%
-- --------------------------------------------------------------------------
local BUTTON_LOGO8_W = 75
local BUTTON_LOGO8_H = 75
local BUTTON_LOGO8_TOP = 4

local BUTTON_LOGO16_SCALE = 75 -- pour 16 boutons
local BUTTON_LOGO16_TOP = 2    -- pour 16 boutons

-- --------------------------------------------------------------------------
-- Réglages d'affichage du logo dans le slider PROP
-- --------------------------------------------------------------------------
local PROP_LOGO_SCALE = 50
local PROP_LOGO_BOTTOM_MARGIN = 6
local PROP_TEXT_TOP_MARGIN = 34

-- --------------------------------------------------------------------------
-- Retourne les réglages visuels selon la hauteur réelle du bouton.
--   Valeurs de retour :
--     baseW, baseH, logoTop, textBottomMargin, logoScale
-- --------------------------------------------------------------------------
local function getButtonLogoLayout(h)
  if h <= 60 then
    return BUTTON_LOGO8_W, BUTTON_LOGO8_H, BUTTON_LOGO16_TOP, 18, BUTTON_LOGO16_SCALE
  end
  return BUTTON_LOGO8_W, BUTTON_LOGO8_H, BUTTON_LOGO8_TOP, 19, 100
end

-- --------------------------------------------------------------------------
-- Retourne le chemin du logo.
--   Un seul dossier est utilisé : Logos8
-- --------------------------------------------------------------------------
local function getButtonLogoPath(logoName)
  if not logoName or logoName == "" then
    return nil
  end

  -- chemin absolu → on ne touche pas
  if string.sub(logoName, 1, 1) == "/" then
    return logoName
  end

  return "/WIDGETS/XANYLVGL/Logos/" .. logoName
end

local function loadButtonLogoBitmap(logoName)
  local path = getButtonLogoPath(logoName)
  if not path then
    return nil
  end

  if buttonLogoBitmaps[path] ~= nil then
    return buttonLogoBitmaps[path]
  end

  local bmp = nil

  if Bitmap and type(Bitmap.open) == "function" then
    local ok, img = pcall(Bitmap.open, path)
    if ok then bmp = img end
  end

  if not bmp and lcd and type(lcd.loadBitmap) == "function" then
    local ok, img = pcall(lcd.loadBitmap, path)
    if ok then bmp = img end
  end

  buttonLogoBitmaps[path] = bmp
  return bmp
end

-- --------------------------------------------------------------------------
-- POD azimutaux (affichage synchro moteurs)
--   POD50x60.png     : moteur actif / synchronisé
--   POD50x60_BW.png  : moteur non synchronisé (grisé)
--
-- Les images sont placées dans :
--   /WIDGETS/XANYLVGL/
--
-- Le masque de synchro est lu dans GV6 :
--   bit0 = POD2
--   bit1 = POD3
--   bit2 = POD4
-- --------------------------------------------------------------------------

local podBitmapColor = false
local podBitmapBW = false
-- --------------------------------------------------------------------------
-- Animation hélice
-- --------------------------------------------------------------------------
local propFrames = {}
local propFrame = { 1, 1, 1, 1 }
local propTimer = { 0, 0, 0, 0 }

local function loadPropFrames()
  if #propFrames > 0 then
    return
  end
  for i = 1,12 do
    local name = "/WIDGETS/XANYLVGL/Images/PROP_anim_"..i..".png"
    local bmp = nil
    if Bitmap and Bitmap.open then
      local ok, img = pcall(Bitmap.open, name)
      if ok then bmp = img end
    end
    if not bmp and lcd and lcd.loadBitmap then
      local ok, img = pcall(lcd.loadBitmap, name)
      if ok then bmp = img end
    end
    propFrames[i] = bmp
  end
end

local function loadPodBitmaps()
  if podBitmapColor ~= false then
    return podBitmapColor, podBitmapBW
  end

  podBitmapColor = nil
  podBitmapBW = nil

  -- ouverture avec Bitmap.open si disponible
  if Bitmap and type(Bitmap.open) == "function" then
    local ok1, bmp1 = pcall(Bitmap.open, "/WIDGETS/XANYLVGL/Images/POD50x60.png")
    if ok1 then podBitmapColor = bmp1 end

    local ok2, bmp2 = pcall(Bitmap.open, "/WIDGETS/XANYLVGL/Images/POD50x60_BW.png")
    if ok2 then podBitmapBW = bmp2 end
  end

  -- fallback lcd.loadBitmap
  if lcd and type(lcd.loadBitmap) == "function" then
    if not podBitmapColor then
      local ok1, bmp1 = pcall(lcd.loadBitmap, "/WIDGETS/XANYLVGL/Images/POD50x60.png")
      if ok1 then podBitmapColor = bmp1 end
    end

    if not podBitmapBW then
      local ok2, bmp2 = pcall(lcd.loadBitmap, "/WIDGETS/XANYLVGL/Images/POD50x60_BW.png")
      if ok2 then podBitmapBW = bmp2 end
    end
  end

  return podBitmapColor, podBitmapBW
end

-- --------------------------------------------------------------------------
-- Lecture du masque de synchronisation (GV6)
--
-- GV6 encode quels pods suivent le POD1
--
-- bit0 = POD2
-- bit1 = POD3
-- bit2 = POD4
--
-- Exemple :
-- GV6 = 5 (101b)
--   POD2 sync
--   POD4 sync
-- --------------------------------------------------------------------------

getSyncMask = function()

  if widget.api and widget.api.gv_get then
    local v = widget.api.gv_get(26)
    if v ~= nil then return v end
  end

  -- fallback direct sur la vraie GV6/FM0
  local okm, vm = pcall(function() return model.getGlobalVariable(5, 0) end)
  if okm and vm ~= nil then
    return vm
  end

  -- fallback si API absente
  if getValue then
    local ok, v = pcall(getValue, "GV6")
    if ok and v ~= nil then
      return v
    end
  end

  return sharedSyncMask or 0
end

local function isPodPresent(id)
  if id == 1 then
    return true
  end

  -- La synchro moteur ne doit prendre en compte que les instances
  -- réellement configurées en ANGLE+PROP.
  if not isAnglePropWidgetPresent(id) then
    return false
  end

  local pods = widget.config and widget.config.pods
  if type(pods) ~= "table" then
    return isWidgetPresent(id)
  end

  local v = pods[id]
  if v == nil then
    v = pods["pod"..tostring(id)]
  end
  if v == nil then
    return isWidgetPresent(id)
  end

  return (v == true) or (v == 1)
end

local function getConfiguredSyncMask()
  local mask = 0
  if isPodPresent(2) then mask = mask + 1 end
  if isPodPresent(3) then mask = mask + 2 end
  if isPodPresent(4) then mask = mask + 4 end
  return mask
end

local function applySyncState()
  local id = (widget.options and widget.options.ID) or 1
  local mode = (widget.options and widget.options.MODE) or 0
  local synchroEnabled = false

  if widget.options then
    synchroEnabled = (widget.options.Synchro == true) or (widget.options.Synchro == 1)
  end

  -- IMPORTANT :
  -- normalizeModeChoice() est défini plus bas dans le fichier.
  -- Ici on refait la normalisation minimale localement pour ne pas dépendre
  -- de l'ordre historique des fonctions dans buttons.lua.
  mode = tonumber(mode) or 0
  if mode >= 1 and mode <= 5 then
    mode = mode - 1
  end
  if mode < 0 then mode = 0 end
  if mode > 4 then mode = 4 end

  -- IMPORTANT :
  -- Seule l'instance #1 pilote l'état global de synchro. Les autres widgets
  -- ne doivent jamais réécrire GV6.
  if id ~= 1 then
    return
  end

  -- Si l'instance #1 n'est pas en ANGLE+PROP, ou si l'option Synchro est
  -- décochée, alors la synchro réelle doit être forcée à OFF. Cela évite de
  -- conserver un ancien masque GV6 non nul d'une session précédente.
  if mode ~= 4 or not synchroEnabled then
    widget.syncButtonState = 0
    sharedSyncMask = 0
    _G.XANYCTL_syncMaskShared = 0
    if widget.api and widget.api.gv_set then
      widget.api.gv_set(26, 0)
    end
    pcall(function() model.setGlobalVariable(5, 0, 0) end)
    return
  end

  local mask = 0
  if widget.syncButtonState ~= 0 then
    mask = getConfiguredSyncMask()
  end

  sharedSyncMask = mask
  _G.XANYCTL_syncMaskShared = mask

  if widget.api and widget.api.gv_set then
    widget.api.gv_set(26, mask)
  end
  pcall(function() model.setGlobalVariable(5, 0, mask) end)
end

-- --------------------------------------------------------------------------
-- Lecture PROP / ANGLE stockés par le widget principal
--
-- Mapping réel du projet :
--   GV7 = PROP  (0..255)
--   GV8 = ANGLE (0..359°)
--
-- NOTE :
--   Les GV17/GV18/GV19 ne sont que "virtuelles" dans certains échanges de
--   conception. Sur la radio, on lit bien GV7/GV8.
-- --------------------------------------------------------------------------

local function getPropValue()
  return getLocalPropValue()
end

local function getAngleValue()
  return getLocalAngleValue()
end

-- --------------------------------------------------------------------------
-- Synchro forcée GV7 / GV8
--
-- IMPORTANT :
--   Cette synchronisation recopie physiquement PROP/ANGLE du POD1 (FM0)
--   vers les pods esclaves (FM1..FM3) quand le bouton SYNCHRO de l'instance #1
--   est sur ON en mode ANGLE+PROP.
--
--   Ce n'est pas la logique "théorique" la plus élégante, mais elle permet
--   d'obtenir une synchro visible et robuste même si les FMs restent séparés.
-- --------------------------------------------------------------------------
_G.XANYCTL_forcedSyncState = _G.XANYCTL_forcedSyncState or {
  active = false,
  prop = {},
  angle = {},
}
local sharedForcedSyncState = _G.XANYCTL_forcedSyncState

-- --------------------------------------------------------------------------
-- Synchro forcée GV7 / GV8 avec sauvegarde / restauration
--
-- IMPORTANT :
--   - OFF : chaque pod garde ses propres valeurs FM
--   - ON  : on sauvegarde d'abord FM1..FM3 puis on recopie FM0 -> FM1..FM3
--   - retour OFF : on restaure les anciennes valeurs locales FM1..FM3
--
-- Cette logique permet d'obtenir une vraie synchro visible et robuste,
-- tout en conservant l'indépendance immédiate quand le bouton repasse OFF.
-- --------------------------------------------------------------------------
local function applyForcedAnglePropSync()
  local id = (widget.options and widget.options.ID) or 1
  id = tonumber(id) or 1
  if id ~= 1 then
    return
  end

  local mode = normalizeModeChoice((widget.options and widget.options.MODE) or 0)

  local synchroEnabled = false
  if widget.options then
    synchroEnabled = (widget.options.Synchro == true) or (widget.options.Synchro == 1)
  end

  local realMask = getSyncMask() or 0
  local shouldForce = (mode == 4) and synchroEnabled and (realMask ~= 0)

  if shouldForce then
    if not sharedForcedSyncState.active then
      for fm = 1, 3 do
        local okp, vp = pcall(function() return model.getGlobalVariable(6, fm) end) -- vraie GV7
        local oka, va = pcall(function() return model.getGlobalVariable(7, fm) end) -- vraie GV8
        sharedForcedSyncState.prop[fm] = (okp and vp ~= nil) and vp or 0
        sharedForcedSyncState.angle[fm] = (oka and va ~= nil) and va or 0
      end
      sharedForcedSyncState.active = true
    end

    local prop0 = getPropValueForPod(1)
    local angle0 = getAngleValueForPod(1)

    for fm = 1, 3 do
      pcall(function() model.setGlobalVariable(6, fm, prop0) end) -- vraie GV7 -> FM1..FM3
      pcall(function() model.setGlobalVariable(7, fm, angle0) end) -- vraie GV8 -> FM1..FM3
    end
    return
  end

  if sharedForcedSyncState.active then
    for fm = 1, 3 do
      local vp = sharedForcedSyncState.prop[fm]
      local va = sharedForcedSyncState.angle[fm]
      if vp ~= nil then
        pcall(function() model.setGlobalVariable(6, fm, vp) end)
      end
      if va ~= nil then
        pcall(function() model.setGlobalVariable(7, fm, va) end)
      end
    end
    sharedForcedSyncState.prop = {}
    sharedForcedSyncState.angle = {}
    sharedForcedSyncState.active = false
  end
end

-- --------------------------------------------------------------------------
-- Dessin d'un pod orientable
--
-- Si lcd.drawBitmapRotated() existe, on l'utilise.
-- Sinon on fait un fallback simple en bitmap fixe.
-- --------------------------------------------------------------------------

local function drawPod(x, y, angle, podBmp, propBmp, label)

  if not podBmp then return end

  -- IMPORTANT :
  --   En mode LVGL, on crée les pods avec lvgl.image().
  --   On garde au maximum la logique XANYCTL existante :
  --     - la présence du pod reste décidée dans drawPods()
  --     - si propBmp est nil, on n'affiche PAS d'hélice
  --     - si propBmp existe, PROP_anim_1 reste visible sous 5
  --       puis les autres frames sont utilisées au-dessus de 5
  if lvgl then
    local podFile = "/WIDGETS/XANYLVGL/Images/POD50x60_BW.png"
    if podBmp == podBitmapColor then
      podFile = "/WIDGETS/XANYLVGL/Images/POD50x60.png"
    end

    lvgl.image({
      x = x,
      y = y,
      w = 50,
      h = 60,
      file = podFile,
      fill = false
    })


    if propBmp then
      local propFile = "/WIDGETS/XANYLVGL/Images/PROP_anim_1.png"
      for i = 1, #propFrames do
        if propFrames[i] == propBmp then
          propFile = "/WIDGETS/XANYLVGL/Images/PROP_anim_" .. tostring(i) .. ".png"
          break
        end
      end
      
	  -- IMPORTANT :
	  --   Correction ciblée du mode LVGL.
	  --   buttons_XANYCTL.lua fonctionne déjà avec la logique de présence
	  --   dans drawPods(), donc on ne touche pas aux lignes 1094 à 1104.
	  --   Ici on sécurise seulement la frame affichée pour éviter l'erreur
	  --   de la ligne 818 et garder l'affichage couleur/gris piloté par
	  --   la présence réelle du pod comme dans XANYCTL.
      local podIndex = tonumber(label) or 1
      local frameIndex = 1
      if podIndex >= 1 and podIndex <= 4 then
        frameIndex = propFrame[podIndex] or 1
      end
      if propBmp == propFrames[1] then
        frameIndex = 1
      end
      propFile = "/WIDGETS/XANYLVGL/Images/PROP_anim_" .. tostring(frameIndex) .. ".png"
	  -- position hélice
      lvgl.image({
        x = x - 3,
        y = y + 17,
        w = 18,
        h = 36,
        file = propFile,
        fill = false
      })
    end

    -- numéro du pod
    if label then
      pcall(function()
        lvgl.label({
          x = x + 19,
          y = y + 14,
          w = 20,
          text = tostring(label),
          color = BLACK,
          font = MIDSIZE,
          align = CENTER
        })
      end)
    end
    return
  end

  local cx = x + 25
  local cy = y + 30

  if lcd and type(lcd.drawBitmapRotated) == "function" then
    pcall(function()
      lcd.drawBitmapRotated(podBmp, cx, cy, angle)
    end)
  else
    local ok = pcall(function() lcd.drawBitmap(podBmp, x, y) end)
    if not ok then
      pcall(function() lcd.drawBitmap(x, y, podBmp) end)
    end
  end

  if propBmp then
    local ok = pcall(function() lcd.drawBitmap(propBmp, x + 0, y + 12) end)-- position hélice (alignée avec PROP_anim_X.png)
    if not ok then
      pcall(function() lcd.drawBitmap(x + 0, y + 12, propBmp) end)-- position hélice (alignée avec PROP_anim_X.png)
    end
  end

  -- numéro du pod
  if label then
    pcall(function()
      lvgl.label({
        x = x + 16,
        y = y + 14,
        w = 20,
        text = tostring(label),
        color = BLACK,
        font = MIDSIZE,
        align = CENTER
      })
    end)
  end
end

local function drawSynchroMark(x, y)
  if lvgl then
    lvgl.image({
      x = x + 13,
      y = y - 2,
      w = 30,
      h = 30,
      file = "/WIDGETS/XANYLVGL/Images/Synchro30x30.png",
      fill = false
    })
    return
  end
  local bmp = synchroBitmap
  if bmp == false then
    bmp = nil
    if Bitmap and type(Bitmap.open) == "function" then
      local ok, img = pcall(Bitmap.open, "/WIDGETS/XANYLVGL/Images/Synchro30x30.png")
      if ok then bmp = img end
    end
    if not bmp and lcd and type(lcd.loadBitmap) == "function" then
      local ok, img = pcall(lcd.loadBitmap, "/WIDGETS/XANYLVGL/Images/Synchro30x30.png")
      if ok then bmp = img end
    end
    synchroBitmap = bmp
  end

  if not bmp or not lcd then return end

  local ok = pcall(function() lcd.drawBitmap(bmp, x + 13, y - 2) end)-- réglage du logo synchro
  if not ok then
    pcall(function() lcd.drawBitmap(x + 13, y - 2, bmp) end)-- réglage du logo synchro
  end
end

-- --------------------------------------------------------------------------
-- Dessin des pods (mode ANGLE+PROP)
--
-- Les pods sont affichés en carré en haut à gauche du widget
--
--   POD1   POD2
--   POD3   POD4
--
-- POD1 = moteur maître (toujours couleur)
-- POD2/3/4 = couleur si synchronisé, sinon gris
--
-- Synchro lue dans GV6 :
--   bit0 = POD2
--   bit1 = POD3
--   bit2 = POD4
--
-- VERSION ACTUELLE DE VALIDATION :
--   - POD2 forcé en couleur
--   - POD3/POD4 selon le masque GV6
--   - animation hélice basée sur GV7
--   - orientation pod basée sur GV8
-- --------------------------------------------------------------------------


local function buildAnglePropDebugLine()
  local buttonState = (widget.syncButtonState ~= 0) and 1 or 0
  local cfgMask = getConfiguredSyncMask()
  local mask = getSyncMask()
  local directMask = 0
  local okm, vm = pcall(function() return model.getGlobalVariable(5, 0) end)
  if okm and vm ~= nil then
    directMask = math.floor(tonumber(vm) or 0)
  end

  local p2Present = isPodPresent(2) and 1 or 0
  local a2Present = isAnglePropWidgetPresent(2) and 1 or 0

  local prop1  = getPropValueForPod(1)
  local angle1 = getAngleValueForPod(1)
  local prop2  = getPropValueForPod(2)
  local angle2 = getAngleValueForPod(2)
  
  local Dbg = "DBG B"..tostring(buttonState)
      .." C"..tostring(cfgMask)
      .." M"..tostring(mask)
      .." D"..tostring(directMask)
      .." P2"..tostring(p2Present).."A"..tostring(a2Present)
      .." P1:"..tostring(prop1)
      .." A1:"..tostring(angle1)
      .." P2:"..tostring(prop2)
      .." A2:"..tostring(angle2)
	  
  -- Debug ANGLE+PROP
  if label then
    pcall(function()
      lvgl.label({
        x = x ,
        y = y + 14,
        w = 20,
        text = tostring(Dbg),
        color = BLACK,
        font = SMLSIZE
      })
    end)
  end	  
	  
end

local function drawPods()

  local podColor, podBW = loadPodBitmaps()
  if not podColor then return end

  local mask  = getSyncMask()

  local p1Present = isPodPresent(1)
  local p2Present = isPodPresent(2)
  local p3Present = isPodPresent(3)
  local p4Present = isPodPresent(4)

  -- ------------------------------------------------------------
  -- Masque de synchro réel :
  --   bit0 = POD2
  --   bit1 = POD3
  --   bit2 = POD4
  -- ------------------------------------------------------------
  local sync2 = p2Present and ((math.floor(mask / 1) % 2) == 1)
  local sync3 = p3Present and ((math.floor(mask / 2) % 2) == 1)
  local sync4 = p4Present and ((math.floor(mask / 4) % 2) == 1)

  -- ------------------------------------------------------------
  -- lecture des valeurs de chaque pod
  -- ------------------------------------------------------------
  local prop1  = getPropValueForPod(1)
  local angle1 = getAngleValueForPod(1)

  -- IMPORTANT :
  --   L'affichage lit toujours les vraies valeurs de chaque FM.
  --   Si la synchro réelle est ON, applyForcedAnglePropSync() a déjà copié
  --   FM0 -> FM1..FM3. Si elle est OFF, chaque pod reste indépendant.
  local prop2  = getPropValueForPod(2)
  local angle2 = getAngleValueForPod(2)

  local prop3  = getPropValueForPod(3)
  local angle3 = getAngleValueForPod(3)

  local prop4  = getPropValueForPod(4)
  local angle4 = getAngleValueForPod(4)

  -- ------------------------------------------------------------
  -- choix des images selon présence réelle du pod
  --
  -- IMPORTANT :
  --   - pod présent     -> image couleur
  --   - pod absent      -> image grise
  --   - la synchro ne change PAS la couleur du pod
  -- ------------------------------------------------------------
  local pod1 = p1Present and podColor or podBW
  local pod2 = p2Present and podColor or podBW
  local pod3 = p3Present and podColor or podBW
  local pod4 = p4Present and podColor or podBW

  -- ------------------------------------------------------------
  -- position du carré de pods
  -- ------------------------------------------------------------
  local startX = zone.x + 10
  local startY = zone.y + 45

  local dx = 60
  local dy = 70

  -- ------------------------------------------------------------
  -- animation hélice
  -- ------------------------------------------------------------
  loadPropFrames()

  local function updatePropAnim(index, prop)
    if prop > 5 then-- remplace 5 par 0 à la fin !!!!!
      propTimer[index] = propTimer[index] + math.max(1, math.floor(prop / 8))
      if propTimer[index] > 20 then
        propTimer[index] = 0
        propFrame[index] = propFrame[index] + 1
        if propFrame[index] > 4 then
          propFrame[index] = 1
        end
      end
    else
      propTimer[index] = 0
      propFrame[index] = 1
    end
  end

  updatePropAnim(1, prop1)
  updatePropAnim(2, prop2)
  updatePropAnim(3, prop3)
  updatePropAnim(4, prop4)

  -- ------------------------------------------------------------
  -- disposition :
  --
  --  POD1 POD2
  --  POD3 POD4
  -- ------------------------------------------------------------
  local propBmpAnim1 = propFrames[propFrame[1]] or propFrames[1]
  local propBmpAnim2 = propFrames[propFrame[2]] or propFrames[1]
  local propBmpAnim3 = propFrames[propFrame[3]] or propFrames[1]
  local propBmpAnim4 = propFrames[propFrame[4]] or propFrames[1]

  -- IMPORTANT :
  --   Si PROP < 5, l'hélice reste visible (PROP_anim_1) mais ne tourne pas.
  --   Si le pod est absent, on n'affiche aucune hélice.
  -- IMPORTANT :
  --   On garde la couleur des pods selon leur présence,
  --   mais l'hélice reste visible sur les 4 pods.
  --   Sous 5 -> PROP_anim_1 fixe
  --   Au-dessus de 5 -> animation normale
  local pod1Prop = p1Present and (((prop1 > 5) and propBmpAnim1) or propFrames[1]) or nil

  -- IMPORTANT :
  --   On ne touche PAS à la détection de présence des pods.
  --   On garde donc la logique XANYCTL pour les pods eux-mêmes.
  --   Ici on force seulement l'affichage de l'hélice sur POD2..POD4 :
  --     - PROP < 5  -> PROP_anim_1 visible et fixe
  --     - PROP > 5  -> frames animées
  local pod2Prop = p2Present and (((prop2 > 5) and propBmpAnim2) or propFrames[1]) or nil
  local pod3Prop = p3Present and (((prop3 > 5) and propBmpAnim3) or propFrames[1]) or nil
  local pod4Prop = p4Present and (((prop4 > 5) and propBmpAnim4) or propFrames[1]) or nil



  drawPod(startX,      startY,      angle1, pod1, pod1Prop, 1)
  drawPod(startX + dx, startY,      angle2, pod2, pod2Prop, 2)
  drawPod(startX,      startY + dy, angle3, pod3, pod3Prop, 3)
  drawPod(startX + dx, startY + dy, angle4, pod4, pod4Prop, 4)

  if sync2 then drawSynchroMark(startX + dx, startY) end
  if sync3 then drawSynchroMark(startX, startY + dy) end
  if sync4 then drawSynchroMark(startX + dx, startY + dy) end
end

local function loadLogoBitmap()
  if logoBitmap ~= false then
    return logoBitmap
  end

  logoBitmap = nil
  if Bitmap and type(Bitmap.open) == "function" then
    local ok, bmp = pcall(Bitmap.open, "/WIDGETS/XANYLVGL/Images/RCUL30x39.png")
    if ok then
      logoBitmap = bmp
      return logoBitmap
    end
  end
  if lcd and type(lcd.loadBitmap) == "function" then
    local ok, bmp = pcall(lcd.loadBitmap, "/WIDGETS/XANYLVGL/Images/RCUL30x39.png")
    if ok then
      logoBitmap = bmp
      return logoBitmap
    end
  end
  return nil
end

local function loadLogoBitmapCompact()
  if logoBitmapCompact ~= false then
    return logoBitmapCompact
  end

  logoBitmapCompact = nil
  if Bitmap and type(Bitmap.open) == "function" then
    local ok, bmp = pcall(Bitmap.open, "/WIDGETS/XANYLVGL/Images/RCUL50x68.png")
    if ok then
      logoBitmapCompact = bmp
      return logoBitmapCompact
    end
  end
  if lcd and type(lcd.loadBitmap) == "function" then
    local ok, bmp = pcall(lcd.loadBitmap, "/WIDGETS/XANYLVGL/Images/RCUL50x68.png")
    if ok then
      logoBitmapCompact = bmp
      return logoBitmapCompact
    end
  end
  return nil
end

local function loadSynchroBitmap()
  if synchroBitmap ~= false then
    return synchroBitmap
  end

  synchroBitmap = nil
  if Bitmap and type(Bitmap.open) == "function" then
    local ok, bmp = pcall(Bitmap.open, "/WIDGETS/XANYLVGL/Images/Synchro30x30.png")
    if ok then
      synchroBitmap = bmp
      return synchroBitmap
    end
  end
  if lcd and type(lcd.loadBitmap) == "function" then
    local ok, bmp = pcall(lcd.loadBitmap, "/WIDGETS/XANYLVGL/Images/Synchro30x30.png")
    if ok then
      synchroBitmap = bmp
      return synchroBitmap
    end
  end
  return nil
end

local function drawHeaderLogo()
  local bmp = loadLogoBitmap()
  if not bmp or not lcd or type(lcd.drawBitmap) ~= "function" then
    return 0
  end

  local ok = pcall(function() lcd.drawBitmap(bmp, zone.x + 2, zone.y + 1) end)
  if not ok then
    pcall(function() lcd.drawBitmap(zone.x + 2, zone.y + 1, bmp) end)
  end
  return 34
end
-- --------------------------------------------------------------------------
-- Chargement libGUI (pattern Multiswitch)
-- --------------------------------------------------------------------------
local function loadGUI()
  if not libGUI then
    if not libGUI_chunk then
      libGUI_chunk = loadScript("/WIDGETS/LibGUI/libgui.lua")
    end
    if libGUI_chunk then
      libGUI = libGUI_chunk()
    end
  end
  return libGUI
end

-- --------------------------------------------------------------------------
-- Helpers d'affichage : rectangle arrondi (fallback si non dispo)
-- --------------------------------------------------------------------------
local function drawRoundRect(gui, x, y, w, h, color, radius)
  radius = radius or 14

  -- certains libGUI exposent drawFilledRoundRect(gui, x,y,w,h,color,r)
  if libGUI and type(libGUI.drawFilledRoundRect) == "function" then
    return libGUI.drawFilledRoundRect(gui, x, y, w, h, color, radius)
  end
  -- d'autres exposent gui.drawFilledRoundRect(...)
  if gui and type(gui.drawFilledRoundRect) == "function" then
    return gui.drawFilledRoundRect(x, y, w, h, color, radius)
  end

  -- fallback : rectangle classique
  if gui and type(gui.drawFilledRectangle) == "function" then
    return gui.drawFilledRectangle(x, y, w, h, color)
  end
end
-- --------------------------------------------------------------------------
-- drawShadowedRoundRect()
--   Dessine un rectangle arrondi avec une ombre douce (optionnelle).
--   L'ombre est simulée par 1 à 2 rectangles décalés (sans alpha, compatible EdgeTX).
-- --------------------------------------------------------------------------
local function drawShadowedRoundRect(gui, x, y, w, h, fillColor, radius)
  radius = radius or 14
  if isShadowEnabled() then
    -- Ombre douce: 2 passes décalées
    drawRoundRect(gui, x + 2, y + 2, w, h, COLOR_THEME_SECONDARY2, radius)
    drawRoundRect(gui, x + 1, y + 1, w, h, COLOR_THEME_SECONDARY3, radius)
  end
  drawRoundRect(gui, x, y, w, h, fillColor, radius)
end

-- --------------------------------------------------------------------------
-- Mode -> (nb boutons, présence PROP)
-- --------------------------------------------------------------------------
local function modeToLayout(mode)
  if mode == 4 then
    return 0, true
  end
  local nbtn = (mode == 0 or mode == 1) and 8 or 16
  local hasProp = (mode == 1 or mode == 3)
  return nbtn, hasProp
end

-- --------------------------------------------------------------------------
-- Construit GUI + contrôles
-- --------------------------------------------------------------------------
local controls = {}
local currentLayoutKey = nil

local function initGUI()
  if lvgl then
    return true
  end
  local lg = loadGUI()
  if not lg then return nil end
  gui = lg.newGUI()
  return gui
end

-- Bouton toggle (ON/OFF)
local function makeToggleButton(x, y, w, h, idx, label, radius, logo)
  if lvgl then
    local offCol, onCol = getOffOnColors()
    -- IMPORTANT :
    --   En LVGL, le texte natif du bouton peut ne pas être affiché
    --   de manière fiable selon le mode/layout. On le dessine donc
    --   toujours avec lvgl.label(), avec ou sans logo.
    local textValue = ""

    lvgl.button({
      x = x,
      y = y,
      w = w,
      h = h,
      text = textValue,
      color = function()
        return (widget.api.gv_get(idx, 0) ~= 0) and onCol or offCol
      end,
      textColor = BLACK,
      cornerRadius = radius or 10,
      font = logo and SMLSIZE or MIDSIZE,
      press = function()
        local cur = widget.api.gv_get(idx, 0)
        local newVal = (cur == 0) and 1 or 0
        widget.api.gv_set(idx, newVal)
        -- IMPORTANT :
        --   On laisse la couleur refléter l'état réel via la fonction color().
        --   On ne force pas l'état "checked" natif du bouton LVGL ici,
        --   car il peut afficher une couleur interne différente (rouge).
        return 0
      end
    })

    if logo then
      local path = getButtonLogoPath(logo)

      if path then
        lvgl.image({
          x = x + 4,
          y = y + 4,
          w = w - 8,
          h = h - 24,
          file = path,
          fill = false
        })
      end

      lvgl.label({
        x = x + 4,
        y = y + h - 18,
        w = w - 8,
        text = tostring(label or idx),
        color = BLACK,
        font = SMLSIZE,
        align = CENTER
      })
    else
      lvgl.label({
        x = x + 4,
        y = y + math.floor((h - 18) / 2),
        w = w - 8,
        text = tostring(label or idx),
        color = BLACK,
        font = MIDSIZE,
        align = CENTER
      })
    end

    return true
  end

  local self = {
    idx = idx,
    label = label or tostring(idx),
    radius = radius or 14,
    logo = logo,
    disabled = false,
    hidden = false,
  }

  function self.draw(focused)
    local v = widget.api.gv_get(idx, 0)
    local offCol, onCol = getOffOnColors()
    local bg = (v ~= 0) and onCol or offCol
    local fg = (v ~= 0) and COLOR_THEME_PRIMARY3 or COLOR_THEME_SECONDARY3
    local br = focused and COLOR_THEME_FOCUS or COLOR_THEME_SECONDARY2

    drawShadowedRoundRect(gui, x, y, w, h, bg, self.radius)
    gui.drawRectangle(x, y, w, h, br)

    -- Ajout logo optionnel défini dans le fichier modèle/TEMPLATE.lua
    local textY = y + h/2
    local textFlags = CENTER + VCENTER + fg
    if self.logo then
      local bmp = loadButtonLogoBitmap(self.logo)
      if bmp and lcd and type(lcd.drawBitmap) == "function" then
        local defW, defH, logoTop, textBottomMargin, logoScale = getButtonLogoLayout(h)
        local bw, bh = getBitmapSizeSafe(bmp)
        local lw = bw or defW
        local lh = bh or defH
        local drawW = math.floor((lw * logoScale) / 100 + 0.5)
        local drawH = math.floor((lh * logoScale) / 100 + 0.5)

        -- centrage réel basé sur la taille affichée (avec scale éventuel)
        local logoX = x + math.floor((w - drawW) / 2)
        local logoY = y + logoTop

        -- drawBitmap(bitmap, x, y [, scale]) si disponible
        local ok = pcall(function() lcd.drawBitmap(bmp, logoX, logoY, logoScale) end)
        if not ok then
          ok = pcall(function() lcd.drawBitmap(logoX, logoY, bmp, logoScale) end)
        end
        if not ok then
          ok = pcall(function() lcd.drawBitmap(bmp, logoX, logoY) end)
        end
        if not ok then
          pcall(function() lcd.drawBitmap(logoX, logoY, bmp) end)
        end

        -- Texte à position fixe selon le layout 8/16 boutons
        textY = y + h - textBottomMargin
        textFlags = CENTER + fg
      end
    end

    gui.drawText(x + w/2 + 1, textY, self.label, textFlags)
    gui.drawText(x + w/2,     textY, self.label, textFlags + BOLD)
  end

  function self.onEvent(event, touchState)
    if event == EVT_VIRTUAL_ENTER then
      local v = widget.api.gv_get(idx, 0)
      widget.api.gv_set(idx, (v == 0) and 1 or 0)
    end
  end

  gui.custom(self, x, y, w, h)
  return self
end

-- Bouton momentané (ON tant qu'on appuie)
local function makeMomentaryButton(x, y, w, h, idx, label, radius, logo)
  if lvgl then
    local offCol, onCol = getOffOnColors()
    -- IMPORTANT :
    --   Même logique que makeToggleButton() : le texte est toujours
    --   dessiné par lvgl.label(), pas par le texte natif du bouton.
    local textValue = ""

    lvgl.momentaryButton({
      x = x,
      y = y,
      w = w,
      h = h,
      text = textValue,
      color = function()
        return (widget.api.gv_get(idx, 0) ~= 0) and onCol or offCol
      end,
      textColor = BLACK,
      cornerRadius = radius or 10,
      font = logo and SMLSIZE or MIDSIZE,
      press = function()
        widget.api.gv_set(idx, 1)
      end,
      release = function()
        widget.api.gv_set(idx, 0)
      end,
    })

    if logo then
      local path = getButtonLogoPath(logo)
      if path then
        lvgl.image({
          x = x + 4,
          y = y + 4,
          w = w - 8,
          h = h - 24,
          file = path,
          fill = false
        })
      end

      lvgl.label({
        x = x + 4,
        y = y + h - 18,
        w = w - 8,
        text = tostring(label or idx),
        color = BLACK,
        font = SMLSIZE,
        align = CENTER
      })
    else
      lvgl.label({
        x = x + 4,
        y = y + math.floor((h - 18) / 2),
        w = w - 8,
        text = tostring(label or idx),
        color = BLACK,
        font = MIDSIZE,
        align = CENTER
      })
    end

    return true
  end

  local self = {
    idx = idx,
    label = label or tostring(idx),
    radius = radius or 14,
    logo = logo,
    disabled = false,
    hidden = false,
    value = false,
  }

  function self.draw(focused)
    local v = widget.api.gv_get(idx, 0)
    local offCol, onCol = getOffOnColors()
    local bg = (v ~= 0) and onCol or offCol
    local fg = (v ~= 0) and COLOR_THEME_PRIMARY3 or COLOR_THEME_SECONDARY3
    local br = focused and COLOR_THEME_FOCUS or COLOR_THEME_SECONDARY2

    drawShadowedRoundRect(gui, x, y, w, h, bg, self.radius)
    gui.drawRectangle(x, y, w, h, br)

    -- Ajout logo optionnel défini dans le fichier modèle/TEMPLATE.lua
    local textY = y + h/2
    local textFlags = CENTER + VCENTER + fg
    if self.logo then
      local bmp = loadButtonLogoBitmap(self.logo)
      if bmp and lcd and type(lcd.drawBitmap) == "function" then
        local defW, defH, logoTop, textBottomMargin, logoScale = getButtonLogoLayout(h)
        local bw, bh = getBitmapSizeSafe(bmp)
        local lw = bw or defW
        local lh = bh or defH
        local drawW = math.floor((lw * logoScale) / 100 + 0.5)
        local drawH = math.floor((lh * logoScale) / 100 + 0.5)

        -- centrage réel basé sur la taille affichée (avec scale éventuel)
        local logoX = x + math.floor((w - drawW) / 2)
        local logoY = y + logoTop

        -- drawBitmap(bitmap, x, y [, scale]) si disponible
        local ok = pcall(function() lcd.drawBitmap(bmp, logoX, logoY, logoScale) end)
        if not ok then
          ok = pcall(function() lcd.drawBitmap(logoX, logoY, bmp, logoScale) end)
        end
        if not ok then
          ok = pcall(function() lcd.drawBitmap(bmp, logoX, logoY) end)
        end
        if not ok then
          pcall(function() lcd.drawBitmap(logoX, logoY, bmp) end)
        end

        -- Texte à position fixe selon le layout 8/16 boutons
        textY = y + h - textBottomMargin
        textFlags = CENTER + fg
      end
    end

    -- effet épaissi du texte (double tracé)
    gui.drawText(x + w/2 + 1, textY, self.label, textFlags)
    gui.drawText(x + w/2,     textY, self.label, textFlags + BOLD)
  end

  function self.onEvent(event, touchState)
    -- tactile : press -> ON / release -> OFF
    if event == EVT_TOUCH_FIRST then
      if self.covers(touchState.x, touchState.y) then
        gui.editing = true
        widget.api.gv_set(idx, 1)
      end
    elseif event == EVT_TOUCH_BREAK or event == EVT_VIRTUAL_EXIT then
      if gui.editing then
        gui.editing = false
        widget.api.gv_set(idx, 0)
      end
    elseif event == EVT_VIRTUAL_ENTER_LONG then
      gui.editing = true
      widget.api.gv_set(idx, 1)
    end
  end

  gui.custom(self, x, y, w, h)
  return self
end

-- Slider vertical PROP (0..255) - uniquement modes +PROP
local function makePropSlider(x, y, w, h, label, logo)
  if lvgl then
    local offCol, onCol = getOffOnColors()
    local isLargeAngleProp = (h >= 120)

    lvgl.rectangle({
      x = x,
      y = y,
      w = w,
      h = h,
      color = offCol,
      filled = true,
      rounded = 12
    })

    if isLargeAngleProp then
      local pct = math.floor((getLocalPropValue() * 100 / 255) + 0.5)

      lvgl.label({
        x = x + 4,
        y = y + 4,
        w = w - 8,
        text = tostring(pct) .. "%",
        color = BLACK,
        font = SMLSIZE,
        align = CENTER
      })

      lvgl.verticalSlider({
        x = x + math.floor(w/2),
        y = y + 20,
        h = h - 78,
        min = 0,
        max = 255,
        get = function()
          return getLocalPropValue()
        end,
        set = function(v)
          if isCurrentPodSyncedSlave() then
            return
          end
          setLocalPropValue(v)
        end
      })

      local verticalText = label or "PROP"
      local count = string.len(verticalText)
      local charStep = 14
      local baseY = y + math.floor(h / 2) - math.floor((count * charStep) / 2) + 4

      for i = 1, count do
        local chv = string.sub(verticalText, i, i)
        lvgl.label({
          x = x + math.floor(w/2) - 25,
          y = baseY + (i - 1) * charStep,
          w = 20,
          text = chv,
          color = BLACK,
          font = SMLSIZE,
          align = CENTER
        })
      end

      if logo then
        local path = getButtonLogoPath(logo)
        if path then
          lvgl.image({
            x = x + 8,
            y = y + h - 30,
            w = w - 16,
            h = 20,
            file = path,
            fill = false
          })
        end
      end
    else
      lvgl.label({
        x = x + 4,
        y = y + 4,
        w = w - 8,
        text = label or "PROP",
        color = WHITE,
        font = SMLSIZE
      })

      if logo then
        local path = getButtonLogoPath(logo)
        if path then
          lvgl.image({
            x = x + 6,
            y = y + 22,
            w = w - 12,
            h = 24,
            file = path,
            fill = false
          })
        end
      end

      lvgl.verticalSlider({
        x = x + math.floor(w/2),
        y = y + (logo and 52 or 24),
        h = h - (logo and 80 or 52),
        min = 0,
        max = 255,
        get = function()
          return getLocalPropValue()
        end,
        set = function(v)
          if isCurrentPodSyncedSlave() then
            return
          end
          setLocalPropValue(v)
        end
      })

      lvgl.label({
        x = x + 4,
        y = y + h - 18,
        w = w - 8,
        text = function()
          local pct = math.floor((getLocalPropValue() * 100 / 255) + 0.5)
          return tostring(pct) .. "%"
        end,
        color = WHITE,
        font = SMLSIZE
      })
    end

    return true
  end

  local self = {
    x=x,y=y,w=w,h=h,
    label = label or "PROP",
    logo = logo,
    min = 0,
    max = 255,
    value = getLocalPropValue(),
    delta = 1,
    disabled = false,
    hidden = false,
    editable = true,
  }

  function self.draw(focused)
    local v = widget.api.gv_get(17, 0)
    self.value = v

    -- rail
    -- MODIF UI:
    --   Fond du slider identique aux boutons (rectangle arrondi + bordure).
    local offCol, onCol = getOffOnColors()
    local bg = offCol
    local br = focused and COLOR_THEME_FOCUS or COLOR_THEME_SECONDARY2
    drawShadowedRoundRect(gui, x, y, w, h, bg, 14)
    gui.drawRectangle(x, y, w, h, br)

    local ydot = y + h - (h * (v - self.min) / (self.max - self.min))
    ydot = math.max(y, math.min(y + h, ydot))

    -- "tige" + curseur
    gui.drawFilledRectangle(x + w/2 - 2, y + 4, 4, h - 8, COLOR_THEME_PRIMARY1)

    -- MODIF UI: curseur oblong large (presque largeur du slider)
    local knobW = w - 6
    local knobH = 14
    local kx = x + (w - knobW) / 2
    local ky = ydot - knobH/2
    drawShadowedRoundRect(gui, kx, ky, knobW, knobH, onCol, 7)

    -- Affiche la valeur PROP en pourcentage (0..100%)
    local pct = math.floor(((v - self.min) * 100 / (self.max - self.min)) + 0.5)
    gui.drawText(x + w/2, y - 14, string.format("%d%%", pct), SMLSIZE + CENTER + WHITE)

    -- ----------------------------------------------------------------------
    -- Texte vertical du slider (épaissi)
    -- ----------------------------------------------------------------------
    local verticalText = self.label or "PROP"
    local count = string.len(verticalText)
    local charStep = 18
    local baseY = y + PROP_TEXT_TOP_MARGIN

    for i = 1, count do
      local ch = string.sub(verticalText, i, i)
      local cy = baseY + (i - 1) * charStep
      gui.drawText(x + w/2 + 1, cy, ch, CENTER + WHITE)
      gui.drawText(x + w/2,     cy, ch, CENTER + WHITE + BOLD)
    end

    -- ----------------------------------------------------------------------
    -- Logo optionnel en bas du slider défini dans le fichier modèle/TEMPLATE.lua
    --   prop = { label = "PROP", logo = "MonLogo.png" }
    -- ----------------------------------------------------------------------
    if self.logo then
      local bmp = loadButtonLogoBitmap(self.logo)
      if bmp and lcd and type(lcd.drawBitmap) == "function" then
        local bw, bh = getBitmapSizeSafe(bmp)
        local lw = bw or BUTTON_LOGO8_W
        local lh = bh or BUTTON_LOGO8_H
        local drawW = math.floor((lw * PROP_LOGO_SCALE) / 100 + 0.5)
        local drawH = math.floor((lh * PROP_LOGO_SCALE) / 100 + 0.5)
        local logoX = x + math.floor((w - drawW) / 2)
        local logoY = y + h - drawH - PROP_LOGO_BOTTOM_MARGIN

        local ok = pcall(function() lcd.drawBitmap(bmp, logoX, logoY, PROP_LOGO_SCALE) end)
        if not ok then
          ok = pcall(function() lcd.drawBitmap(logoX, logoY, bmp, PROP_LOGO_SCALE) end)
        end
        if not ok then
          ok = pcall(function() lcd.drawBitmap(bmp, logoX, logoY) end)
        end
        if not ok then
          pcall(function() lcd.drawBitmap(logoX, logoY, bmp) end)
        end
      end
    end
  end

  function self.onEvent(event, touchState)
    if isCurrentPodSyncedSlave() then
      return
    end

    if event == EVT_TOUCH_SLIDE then
      if self.covers(touchState.x, touchState.y) then
        local v = self.min + (self.max - self.min) * (y + h - touchState.y) / h
        v = math.floor(math.max(self.min, math.min(self.max, v)) + 0.5)
        setLocalPropValue(v)
      end
    elseif event == EVT_VIRTUAL_INC then
      setLocalPropValue(math.min(self.max, getLocalPropValue() + self.delta))
    elseif event == EVT_VIRTUAL_DEC then
      setLocalPropValue(math.max(self.min, getLocalPropValue() - self.delta))
    end
  end

  gui.custom(self, x, y, w, h)
  return self
end



local function makeSynchroButton(x, y, w, h)
  if lvgl then
    local offCol, onCol = getOffOnColors()
    lvgl.button({
      x = x, y = y, w = w, h = h,
      text = "SYNCHRO",
      color = function()
      return (widget.syncButtonState ~= 0) and onCol or offCol
      end,
      textColor = BLACK,
      cornerRadius = 8,
      font = SMLSIZE,
      press = function()
        widget.syncButtonState = (widget.syncButtonState ~= 0) and 0 or 1
        applySyncState()
      end
    })
    return true
  end

  local self = {
    disabled = false,
    hidden = false,
  }

  function self.draw(focused)
    local offCol, onCol = getOffOnColors()
    local br = focused and COLOR_THEME_FOCUS or COLOR_THEME_SECONDARY2
    local syncBg = (widget.syncButtonState ~= 0) and onCol or offCol

    drawShadowedRoundRect(gui, x, y, w, h, syncBg, 9)
    gui.drawRectangle(x, y, w, h, br)
    gui.drawText(x + w/2, y + h/2, "SYNCHRO", CENTER + VCENTER + WHITE)
  end

  function self.onEvent(event, touchState)
    if event == EVT_VIRTUAL_ENTER then
      widget.syncButtonState = (widget.syncButtonState ~= 0) and 0 or 1
      applySyncState()
    end
  end

  gui.custom(self, x, y, w, h)
  return self
end

local function makeZeroButton(x, y, w, h)
  if lvgl then
	local offCol, onCol = getOffOnColors()

	lvgl.momentaryButton({
	  x = x, y = y, w = w, h = h,
	  text = "ZERO",

	  -- 🔥 couleur dynamique ON pendant appui uniquement
	  color = function(active)
		return active and onCol or offCol
	  end,

	  textColor = BLACK,
	  cornerRadius = 8,
	  font = SMLSIZE,

	  press = function()
		if isCurrentPodSyncedSlave() then
		  return
		end
		setLocalAngleValue(0)
	  end,
	})
    return true
  end

  local self = {
    disabled = false,
    hidden = false,
  }

  function self.draw(focused)
    local offCol = getOffOnColors()
    local br = focused and COLOR_THEME_FOCUS or COLOR_THEME_SECONDARY2

    drawShadowedRoundRect(gui, x, y, w, h, offCol, 9)
    gui.drawRectangle(x, y, w, h, br)
    gui.drawText(x + w/2, y + h/2, "ZERO", CENTER + VCENTER + WHITE)
  end

  function self.onEvent(event, touchState)
    if isCurrentPodSyncedSlave() then
      return
    end

    if event == EVT_VIRTUAL_ENTER then
      setLocalAngleValue(0)
    end
  end

  gui.custom(self, x, y, w, h)
  return self
end

local function makeAnglePropControl(x, y, w, h)
  if lvgl then
    local function polar(cx, cy, r, deg)
      local rad = math.rad(deg - 90)
      return cx + math.cos(rad) * r, cy + math.sin(rad) * r
    end

    local cx = x + w / 2
    local cy = y + h / 2
    local radius = math.min(w, h) / 2 - 18
    local offCol, onCol = getOffOnColors()
    local br = COLOR_THEME_SECONDARY2

    local function currentAngle()
      local angle = getLocalAngleValue()
      angle = math.floor(tonumber(angle) or 0)
      while angle < 0 do angle = angle + 360 end
      while angle >= 360 do angle = angle - 360 end
      return angle
    end

    local function setAngle(a)
      a = math.floor((tonumber(a) or 0) + 0.5)
      while a < 0 do a = a + 360 end
      while a >= 360 do a = a - 360 end
      setLocalAngleValue(a)
    end

    -- IMPORTANT :
    --   Version LVGL pure du cadran.
    --   L'aiguille et la valeur en degrés sont dynamiques.
    --   L'interaction tactile est relayée explicitement par main.lua vers
    --   widget.handleEvent, au lieu de dépendre de gui.run().
    lvgl.circle({
      x = cx,
      y = cy,
      radius = radius,
      color = BLACK,
      filled = true,
      thickness = 1
    })

    lvgl.circle({
      x = cx,
      y = cy,
      radius = radius,
      color = br,
      thickness = 2
    })

    lvgl.circle({
      x = cx,
      y = cy,
      radius = radius - 12,
      color = br,
      thickness = 2
    })

    for d = 0, 345, 15 do
      local tickLen = 7
      local tickCol = br
      local tickThick = 2
      if d % 90 == 0 then
        tickLen = 16
        tickThick = 3
      elseif d % 45 == 0 then
        tickLen = 12
        tickThick = 2
      end
      if d == 0 then
        tickLen = 20
        tickCol = WHITE
        tickThick = 3
      end
      local r1 = radius - tickLen
      local r2 = radius - 2
      local x1, y1 = polar(cx, cy, r1, d)
      local x2, y2 = polar(cx, cy, r2, d)

      lvgl.line({
        color = tickCol,
        thickness = tickThick,
        rounded = true,
        pts = {
          { math.floor(x1 + 0.5), math.floor(y1 + 0.5) },
          { math.floor(x2 + 0.5), math.floor(y2 + 0.5) }
        }
      })

      if d % 45 == 0 then
        local tr = radius - 28
        if d % 90 == 0 then tr = radius - 31 end
        local tx, ty = polar(cx, cy, tr, d)
        lvgl.label({
          x = tx - 14,
          y = ty - 8,
          w = 28,
          text = tostring(d),
          color = WHITE,
          font = SMLSIZE,
          align = CENTER
        })
      end
    end

    local nx1, ny1 = polar(cx, cy, radius + 2, 0)
    local nx2, ny2 = polar(cx, cy, radius - 10, -4)
    local nx3, ny3 = polar(cx, cy, radius - 10, 4)
    lvgl.triangle({
      color = WHITE,
      opacity = 255,
      pts = {
        { math.floor(nx1 + 0.5), math.floor(ny1 + 0.5) },
        { math.floor(nx2 + 0.5), math.floor(ny2 + 0.5) },
        { math.floor(nx3 + 0.5), math.floor(ny3 + 0.5) }
      }
    })

    lvgl.triangle({
      color = WHITE,
      opacity = 255,
      pts = function()
        local angle = currentAngle()
        local tipx, tipy = polar(cx, cy, radius - 20, angle)
        local bx1, by1 = polar(cx, cy, 18, angle - 10)
        local bx2, by2 = polar(cx, cy, 18, angle + 10)
        return {
          { math.floor(tipx + 0.5), math.floor(tipy + 0.5) },
          { math.floor(bx1 + 0.5), math.floor(by1 + 0.5) },
          { math.floor(bx2 + 0.5), math.floor(by2 + 0.5) }
        }
      end
    })

    lvgl.triangle({
      color = onCol,
      opacity = 255,
      pts = function()
        local angle = currentAngle()
        local tipx2, tipy2 = polar(cx, cy, radius - 22, angle)
        local bx1b, by1b = polar(cx, cy, 15, angle - 8)
        local bx2b, by2b = polar(cx, cy, 15, angle + 8)
        return {
          { math.floor(tipx2 + 0.5), math.floor(tipy2 + 0.5) },
          { math.floor(bx1b + 0.5), math.floor(by1b + 0.5) },
          { math.floor(bx2b + 0.5), math.floor(by2b + 0.5) }
        }
      end
    })

    lvgl.circle({
      x = cx,
      y = cy,
      radius = 11,
      color = WHITE,
      filled = true
    })

    lvgl.circle({
      x = cx,
      y = cy,
      radius = 7,
      color = BLACK,
      filled = true
    })

    lvgl.circle({
      x = cx,
      y = cy,
      radius = 4,
      color = onCol,
      filled = true
    })

    lvgl.rectangle({
      x = cx - 34, y = cy + 20, w = 68, h = 20,
      color = offCol,
      filled = true,
      rounded = 8
    })

    lvgl.label({
      x = cx - 34, y = cy + 16, w = 68,
      text = function()
        return string.format("%03d°", currentAngle())
      end,
      color = BLACK,
      font = MIDSIZE,
      align = CENTER
    })

    widget.handleEvent = function(self, event, touchState)
      if not touchState then return end
      if event ~= EVT_TOUCH_FIRST and event ~= EVT_TOUCH_SLIDE then return end
      if isCurrentPodSyncedSlave() then return end

      -- IMPORTANT :
      --   La version qui "accrochait à l'extérieur" utilisait un mauvais repère
      --   pour le centre du cadran.
      --
      --   En widget LVGL, touchState.x/y est local à la zone du widget.
      --   Le centre tactile du cadran doit donc être exprimé lui aussi en local,
      --   sinon le disque d'accroche est décalé et on a l'impression que seul
      --   l'extérieur fonctionne.
      local tx = touchState.x
      local ty = touchState.y

      local localCx = cx - zone.x
      local localCy = cy - zone.y

      local dx = tx - localCx
      local dy = ty - localCy
      local dist = math.sqrt(dx*dx + dy*dy)

      -- Toute la surface visuelle du cadran + petite marge extérieure.
      local outerRadius = radius + 32

      if dist <= outerRadius then
        local deg = math.deg(math.atan2(dy, dx)) + 90
        if deg < 0 then deg = deg + 360 end
        while deg >= 360 do deg = deg - 360 end
        setAngle(deg)
      end
    end

    return true
  end

  local self = {
    x=x,y=y,w=w,h=h,
    disabled = false,
    hidden = false,
  }

  local function getAngle()
    local a = getLocalAngleValue() or 0
    a = math.floor(tonumber(a) or 0)
    while a < 0 do a = a + 360 end
    while a >= 360 do a = a - 360 end
    return a
  end

  local function setAngle(a)
    a = math.floor((tonumber(a) or 0) + 0.5)
    while a < 0 do a = a + 360 end
    while a >= 360 do a = a - 360 end
    setLocalAngleValue(a)
  end

  local function polar(cx, cy, r, deg)
    local rad = math.rad(deg - 90)
    return cx + math.cos(rad) * r, cy + math.sin(rad) * r
  end

  local function insideRect(tx, ty, rx, ry, rw, rh)
    return tx >= rx and tx <= rx + rw and ty >= ry and ty <= ry + rh
  end

  local function updateFromTouch(tx, ty)
    local cx = x + w / 2
    local cy = y + h / 2
    local dx = tx - cx
    local dy = ty - cy
    local deg = math.deg(math.atan2(dy, dx)) + 90
    if deg < 0 then deg = deg + 360 end
    setAngle(deg)
  end

  function self.draw(focused)
    local cx = x + w / 2
    local cy = y + h / 2
    local radius = math.min(w, h) / 2 - 18
    local angle = getAngle()

    local offCol, onCol = getOffOnColors()
    local br = focused and COLOR_THEME_FOCUS or COLOR_THEME_SECONDARY2
    -- Fond du cadran (noir)
    if lcd.drawFilledCircle then
      lcd.drawFilledCircle(cx, cy, radius-2, BLACK)
    end

    -- Anneau principal bleu
    if lcd.drawCircle then
      lcd.drawCircle(cx, cy, radius, br)
      lcd.drawCircle(cx, cy, radius - 1, br)
      lcd.drawCircle(cx, cy, radius - 12, br)
    end

    -- Graduations fines tous les 15° + repère 0° renforcé
    for d = 0, 345, 15 do
      local tickLen = 7
      local tickCol = br
      if d % 90 == 0 then
        tickLen = 16
      elseif d % 45 == 0 then
        tickLen = 12
      end
      if d == 0 then
        tickLen = 20
        tickCol = WHITE
      end

      local r1 = radius - tickLen
      local r2 = radius - 2
      local x1, y1 = polar(cx, cy, r1, d)
      local x2, y2 = polar(cx, cy, r2, d)
      if lcd.drawLine then
        lcd.drawLine(x1, y1, x2, y2, SOLID, tickCol)
      end

      if d % 45 == 0 then
        local tr = radius - 28
        if d % 90 == 0 then tr = radius - 31 end
        local tx, ty = polar(cx, cy, tr, d)
        gui.drawText(tx, ty, tostring(d), CENTER + VCENTER + SMLSIZE + WHITE)
      end
    end

    -- Petit triangle de cap au 0° (style compas)
    if lcd.drawFilledTriangle then
      local nx1, ny1 = polar(cx, cy, radius + 2, 0)
      local nx2, ny2 = polar(cx, cy, radius - 10, -4)
      local nx3, ny3 = polar(cx, cy, radius - 10, 4)
      lcd.drawFilledTriangle(nx1, ny1, nx2, ny2, nx3, ny3, WHITE)
    end

    -- Aiguille triangulaire avec léger halo blanc
    local tipx, tipy = polar(cx, cy, radius - 20, angle)
    local bx1, by1 = polar(cx, cy, 18, angle - 10)
    local bx2, by2 = polar(cx, cy, 18, angle + 10)

    if lcd.drawFilledTriangle then
      lcd.drawFilledTriangle(tipx, tipy, bx1, by1, bx2, by2, WHITE)
      local tipx2, tipy2 = polar(cx, cy, radius - 22, angle)
      local bx1b, by1b = polar(cx, cy, 15, angle - 8)
      local bx2b, by2b = polar(cx, cy, 15, angle + 8)
      lcd.drawFilledTriangle(tipx2, tipy2, bx1b, by1b, bx2b, by2b, onCol)
    elseif lcd.drawLine then
      lcd.drawLine(cx, cy, tipx, tipy, SOLID, onCol)
      lcd.drawLine(cx, cy, bx1, by1, SOLID, onCol)
      lcd.drawLine(cx, cy, bx2, by2, SOLID, onCol)
    end

    if lcd.drawFilledCircle then
      lcd.drawFilledCircle(cx, cy, 11, WHITE)
      lcd.drawFilledCircle(cx, cy, 7, BLACK)
      lcd.drawFilledCircle(cx, cy, 4, onCol)
    elseif lcd.drawCircle then
      lcd.drawCircle(cx, cy, 11, WHITE)
      lcd.drawCircle(cx, cy, 7, BLACK)
      lcd.drawCircle(cx, cy, 4, onCol)
    end

    -- Cartouche de valeur légèrement plus basse pour dégager le centre du cadran
    local vw = 68
    local vh = 20
    local vx = cx - vw / 2
    local vy = cy + 20
    drawShadowedRoundRect(gui, vx, vy, vw, vh, offCol, 8)
    gui.drawRectangle(vx, vy, vw, vh, br)
    gui.drawText(cx, vy + vh/2, string.format("%03d°", angle), CENTER + VCENTER + MIDSIZE + WHITE)

    self._radius = radius
  end

  function self.onEvent(event, touchState)
    if not touchState then return end

    if event == EVT_TOUCH_FIRST or event == EVT_TOUCH_SLIDE then
      local cx = x + w / 2
      local cy = y + h / 2
      local radius = math.min(w, h) / 2 - 18

      local tx = touchState.x
      local ty = touchState.y

      local dx = tx - cx
      local dy = ty - cy
      local dist = math.sqrt(dx*dx + dy*dy)

      if dist <= (radius + 18) and dist >= 20 then
        updateFromTouch(tx, ty)
      end
    elseif event == EVT_VIRTUAL_ENTER then
      widget.api.gv_set(19, 0)
    end
  end

  gui.custom(self, x, y, w, h)
  return self
end


-- --------------------------------------------------------------------------
-- resetGUI() :
--   Certaines versions de libGUI n'ont pas gui.reset().
--   On tente plusieurs méthodes, sinon on recrée l'objet GUI.
-- --------------------------------------------------------------------------
local function resetGUI()
  if not gui then return end
	if type(gui.reset) == "function" then
	  gui.reset()
	  return
  end
  if type(gui.clear) == "function" then
    gui.clear()
    return
  end
  if type(gui.resetAll) == "function" then
    gui.resetAll()
    return
  end
  -- Fallback universel : recréer un nouvel objet GUI
  local lg = loadGUI()
  if lg and type(lg.newGUI) == "function" then
    gui = lg.newGUI()
  end
end

-- --------------------------------------------------------------------------
-- (Re)build layout selon MODE
-- --------------------------------------------------------------------------
local function buildLayout()
  widget.handleEvent = nil

  if not lvgl then
    if not gui then
      if not initGUI() then return end
    end
    controls = {}
    resetGUI()
  else
    controls = {}
  end

  local mode = normalizeModeChoice((widget.options and widget.options.MODE) or 0)
  local ch   = (widget.options and widget.options.CH) or 8
  local rep  = (widget.options and widget.options.Repeat) or 0

  if lvgl and (zone.w < 350 or zone.h < 200) then
    local title = tostring((widget.config and widget.config.title) or "INSTANCE 1")
    local version = tostring((widget.api and widget.api.VERSION) or "")
    local modeText = "SW8"
    if mode == 1 then modeText = "SW8+PROP"
    elseif mode == 2 then modeText = "SW16"
    elseif mode == 3 then modeText = "SW16+PROP"
    elseif mode == 4 then modeText = "ANGLE+PROP"
    end

    lvgl.image({
      x = zone.x + 6,
      y = zone.y + 25,
      w = 50,
      h = 68,
      file = "/WIDGETS/XANYLVGL/Images/RCUL50x68.png",
      fill = false
    })

    lvgl.label({
      x = zone.x + 6,
      y = zone.y,
      text = "XANYLVGL #" .. tostring((widget.options and widget.options.ID) or 1),
      color = BLACK,
      font = MIDSIZE
    })

    if version ~= "" then
      lvgl.label({
        x = zone.x + zone.w - 40,
        y = zone.y + 10,
        text = "v" .. version,
        color = BLACK,
        font = SMLSIZE
      })
    end

    lvgl.label({
      x = zone.x + 64,
      y = zone.y + 31,
      text = "TITLE: " .. title,
      color = BLACK,
      font = SMLSIZE
    })

    lvgl.label({
      x = zone.x + 64,
      y = zone.y + 47,
      text = "MODE: " .. modeText,
      color = BLACK,
      font = SMLSIZE
    })

    lvgl.label({
      x = zone.x + 64,
      y = zone.y + 63,
      text = "REPEATS: " .. tostring(rep),
      color = BLACK,
      font = SMLSIZE
    })

    lvgl.label({
      x = zone.x + 64,
      y = zone.y + 79,
      text = "CHANNEL: " .. tostring(ch),
      color = BLACK,
      font = SMLSIZE
    })

    currentLayoutKey = "compact_" .. tostring(mode) .. "_" .. tostring(zone.w) .. "x" .. tostring(zone.h)
    return
  end
  if lvgl then
    local id = (widget.options and widget.options.ID) or 1
    local modeText = "SW8"
    if mode == 1 then modeText = "SW8+PROP"
    elseif mode == 2 then modeText = "SW16"
    elseif mode == 3 then modeText = "SW16+PROP"
    elseif mode == 4 then modeText = "ANGLE+PROP"
    end	
	
    lvgl.image({
      x = zone.x + 2,
      y = zone.y,
      w = 30,
      h = 39,
      file = "/WIDGETS/XANYLVGL/Images/RCUL30x39.png",
      fill = false
    })
	
    lvgl.label({
      x = zone.x + 34,
      y = zone.y ,
	  text = tostring(("XANYLVGL #" .. tostring(id)) or "XANYLVGL"),
      color = BLACK,
      font = STDSIZE
    })

    lvgl.label({
      x = zone.x + 34,
      y = zone.y + 18,
	  text = "CH:" .. tostring(ch) .. "  MODE:" .. tostring(mode) .. "(" .. tostring(modeText) .. ")" .. "  REP:" .. tostring(rep),
      color = BLACK,
      font = SMLSIZE
    })

    local version = tostring((widget.api and widget.api.VERSION) or "")
    if version ~= "" then
      lvgl.label({
        x = zone.x + zone.w - 40,
        y = zone.y + 10,
        text = "v" .. version,
        color = BLACK,
        font = SMLSIZE
      })
    end
  end
  -- synchronisation "info" dans GVars (utile à xanytx.lua)
  widget.api.gv_set(32, mode)
  widget.api.gv_set(31, ch)
  widget.api.gv_set(18, rep)

  local nbtn, hasProp = modeToLayout(mode)

  local headerH = 28
  local pad = 6
  local sliderW = hasProp and 58 or 0
  local gridW = zone.w - pad*2 - sliderW - (hasProp and pad or 0)
  local gridH = zone.h - headerH - pad*2

  local x0 = zone.x + pad
  local y0 = zone.y + headerH + pad

  if mode == 4 then
    -- IMPORTANT :
    --   En LVGL, refresh() retourne immédiatement.
    --   On remet donc ici la logique que XANYCTL faisait en refresh():
    --   présence widget, synchro réelle et copie forcée FM0 -> FM1..FM3.
    local id = (widget.options and widget.options.ID) or 1
    markWidgetPresent(id, true)
    applySyncState()
    applyForcedAnglePropSync()

    -- Présentation ANGLE+PROP proche de XANYCTL :
    -- pods à gauche, cadran centré, slider PROP à droite.
    local dialSize = math.min(gridW, gridH)
    if dialSize > 220 then dialSize = 220 end
    local dialX = zone.x + math.floor((zone.w - dialSize) / 2)
    local dialY = y0 + math.floor((gridH - dialSize) / 2)

    if lvgl then
      drawPods()
    end

    controls[#controls+1] = makeAnglePropControl(dialX, dialY, dialSize, dialSize)

    local zw = 72
    local zh = 24
    local zx = zone.x + 8
    local zy = dialY + dialSize - zh - 8
    local sy = zy - zh - 8

    local synchroEnabled = false
    if widget.options then
      synchroEnabled = (widget.options.Synchro == true) or (widget.options.Synchro == 1)
    end

    local id = (widget.options and widget.options.ID) or 1
    id = tonumber(id) or 1

    -- Le bouton SYNCHRO n'existe que sur l'instance #1.
    if id == 1 and synchroEnabled then
      controls[#controls+1] = makeSynchroButton(zx, sy, zw, zh)
    end

    -- ZERO reste local. On le masque seulement sur un esclave réellement
    -- synchronisé, pour éviter une commande locale incohérente.
    if id == 1 or not isCurrentPodSyncedSlave() then
      controls[#controls+1] = makeZeroButton(zx, zy, zw, zh)
    end

    local sx = x0 + gridW + pad
    local sh = math.max(120, gridH - 36)
    local sy = y0 + math.floor((gridH - sh) / 2)
    local slabel = (widget.config.prop and widget.config.prop.label) or "PROP"
    local slogo  = (widget.config.prop and widget.config.prop.logo) or nil
    controls[#controls+1] = makePropSlider(sx, sy, sliderW, sh, slabel, slogo)

    currentLayoutKey = tostring(mode).."_"..tostring(zone.w).."x"..tostring(zone.h)
    return
  end

  local cols = 4
  local rows = (nbtn == 8) and 2 or 4

  local cellW = math.floor(gridW / cols)
  local cellH = math.floor(gridH / rows)

  -- Boutons
  for i=1,nbtn do
    local cfg = (widget.config.buttons and widget.config.buttons[i]) or {}
    local label = cfg.label or tostring(i)
    local typ = cfg.type or "toggle"
    local logo = cfg.logo

    local r = math.floor((i-1)/cols)
    local c = (i-1)%cols
    local x = x0 + c*cellW
    local y = y0 + r*cellH
    local w = cellW - 6
    local h = cellH - 6

    local b
    if typ == "momentary" then
      b = makeMomentaryButton(x, y, w, h, i, label, 10, logo)
    else
      b = makeToggleButton(x, y, w, h, i, label, 10, logo)
    end
    controls[#controls+1] = b
  end

  -- Slider PROP
  if hasProp then
    local sx = x0 + gridW + pad

    -- Slider plus court pour faciliter l'accès aux butées min/max
    -- tout en gardant exactement le reste du code et du layout.
    local sh = math.max(120, gridH - 36)
    local sy = y0 + math.floor((gridH - sh) / 2)

    local slabel = (widget.config.prop and widget.config.prop.label) or "PROP"
    local slogo  = (widget.config.prop and widget.config.prop.logo) or nil
    controls[#controls+1] = makePropSlider(sx, sy, sliderW, sh, slabel, slogo)
  end

  currentLayoutKey = tostring(mode).."_"..tostring(zone.w).."x"..tostring(zone.h)
end


-- --------------------------------------------------------------------------
-- widget.build() : construction UI LVGL/GUI
-- --------------------------------------------------------------------------
function widget:build()
  buildLayout()
end

-- --------------------------------------------------------------------------
-- widget.update() : rebuild si nécessaire
-- --------------------------------------------------------------------------
function widget:update()
  -- En mode LVGL, la reconstruction est pilotée par main.lua.
  if lvgl then
    return
  end
  currentLayoutKey = nil
end

-- --------------------------------------------------------------------------
-- widget.refresh() : header + GUI
-- --------------------------------------------------------------------------
function widget:refresh(event, touchState)
  -- En mode LVGL, on ne repasse PAS dans l'ancien chemin libGUI/lcd.
  -- Sinon on recrée un mélange LVGL + gui.run() qui finit par planter.
  if lvgl then
    if handleSettingsHotZone(event, touchState) then
      return
    end

    -- IMPORTANT :
    --   En mode page LVGL, la fermeture passe par le callback back de la page
    --   settings elle-même. On ne traite donc pas EVT_EXIT_BREAK ici.
    return
  end

  -- ------------------------------------------------------------
  -- Laisser EdgeTX gérer les changements de page en plein écran
  -- ------------------------------------------------------------
  if event == EVT_VIRTUAL_PREV_PAGE or event == EVT_VIRTUAL_NEXT_PAGE then
    return
  end


  local id = (self.options and self.options.ID) or 1
  local mode = normalizeModeChoice((self.options and self.options.MODE) or 0)
  markWidgetPresent(id, mode == 4)
  -- IMPORTANT :
  -- seule l'instance #1 en mode ANGLE+PROP a le droit de pousser l'état
  -- réel de synchro dans GV6. Les autres widgets restent purement locaux.
  applySyncState()
  applyForcedAnglePropSync()

  self.presenceSent = true

  -- Sortie propre de settings :
  --  - fermeture automatique hors plein écran
  --  - fermeture explicite avec RET
  if zone.w < 350 or zone.h < 200 then
    widget.settingsScreenOpen = false
    settingsScreenInitDone = false
  end

  if widget.settingsScreenOpen and event == EVT_EXIT_BREAK then
    widget.settingsScreenOpen = false
    settingsScreenInitDone = false
    return
  end

  if handleSettingsHotZone(event, touchState) then
    return
  end

  if widget.settingsScreenOpen and zone.w >= 350 and zone.h >= 200 then
    publishSettingsContext()
    local scr = loadSettingsScreen()
    if scr then
      if (not settingsScreenInitDone) and type(scr.init) == "function" then
        pcall(scr.init)
        settingsScreenInitDone = true
      end
      if type(scr.run) == "function" then
        scr.run(event, touchState)
        return
      elseif type(scr.refresh) == "function" then
        scr.refresh(event, touchState)
        return
      end
    end
    lcd.drawFilledRectangle(zone.x, zone.y, zone.w, zone.h, GREY)
    lvgl.label(zone.x + 12, zone.y + 10, "SETTINGS", DBLSIZE + BOLD)
    lvgl.label(zone.x + 12, zone.y + 50, "Zone cachee OK", MIDSIZE)
    lvgl.label(zone.x + 12, zone.y + 75, "Touchez en haut a droite pour fermer", SMLSIZE)
    return
  end

  -- ------------------------------------------------------------
  -- Présence widget
  --
  -- IMPORTANT :
  --   Avant, ce bloc écrivait la "présence des pods" dans GV6.
  --   C'était une erreur, car GV6 est déjà utilisé comme MASQUE REEL
  --   DE SYNCHRO (bit0=POD2, bit1=POD3, bit2=POD4).
  --
  --   Conséquence du mélange :
  --     - un widget simplement présent pouvait mettre des bits dans GV6
  --     - drawPods() interprétait alors ces bits comme une vraie synchro
  --     - les hélices / angles semblaient rester synchronisés même OFF
  --
  --   Correction :
  --     - la présence reste suivie uniquement par :
  --         markWidgetPresent()
  --         sharedWidgetPresence
  --         sharedWidgetPresenceSeen
  --     - GV6 reste réservé EXCLUSIVEMENT à la synchro réelle
  --
  --   Donc ici on ne touche plus du tout à GV6.
  -- ------------------------------------------------------------
  if not self.presenceSent then
    self.presenceSent = true
  end

  -- ----------------------------------------------------------------------
  -- Compact mode: when widget is displayed in a small zone (not fullscreen)
  -- show only the widget name, instance number and channel.
  -- ----------------------------------------------------------------------
  if zone.w < 350 or zone.h < 200 then
    local id = (self.options and self.options.ID) or 1
    local ch = (self.options and self.options.CH) or 5
    local mode = normalizeModeChoice((self.options and self.options.MODE) or 0)
	local rep  = (self.options and self.options.Repeat) or 0
	
	local hasTopBar = (zone.y > 0) -- test si la barre du haut est présente
	local yBase = zone.y
    if hasTopBar then
      yBase = zone.y + 4
    end
	
    local modeText = "SW8"
    if mode == 1 then
      modeText = "SW8+PROP"
    elseif mode == 2 then
      modeText = "SW16"
    elseif mode == 3 then
      modeText = "SW16+PROP"
    elseif mode == 4 then
      modeText = "ANGLE+PROP"
    end

    local bmp = loadLogoBitmapCompact()
    if bmp then
	  --if hasTopBar then
        lcd.drawBitmap(bmp, zone.x + 5, yBase + 32)
	  --else
	  --  lcd.drawBitmap(bmp, zone.x + 5, zone.y + (zone.h - 68) / 2)
	  --end
    end

    local tx = zone.x + 60

    local headerY = yBase + 6
    lvgl.label(tx-50, headerY, "XANYLVGL #" .. tostring(id), LEFT + MIDSIZE)
    local version = (widget.api and widget.api.VERSION) or ""
    lvgl.label(tx + 150, headerY + 2, "v" .. version, LEFT + SMLSIZE)

    local title = (cfg and cfg.title) or ("INSTANCE " .. tostring(id))
    lvgl.label(tx, zone.y + 40 , "TITLE: " .. title, LEFT + SMLSIZE)
    lvgl.label(tx, zone.y + 57 , "MODE: " .. tostring(modeText), LEFT + SMLSIZE)
	lvgl.label(tx, zone.y + 74 , "REPEATS: " .. tostring(rep), LEFT + SMLSIZE)
    lvgl.label(tx, zone.y + 91 , "CHANNEL: " .. tostring(ch), LEFT + SMLSIZE)
    return
  end
  if not gui then
    if not initGUI() then
      local msg = (TXT and TXT.NO_LIBGUI_FOUND) or "LibGUI absente"
      lvgl.label(zone.x+2, zone.y+2, msg, MIDSIZE)
      lvgl.label(zone.x+2, zone.y+30, "see https://github.com/EdgeTX/edgetx-sdcard/releases", SMLSIZE)
      return
    end
  end

  local mode = normalizeModeChoice((self.options and self.options.MODE) or 0)
  local ch   = (self.options and self.options.CH) or 5
  local rep  = (self.options and self.options.Repeat) or 0

  local key = tostring(mode).."_"..tostring(zone.w).."x"..tostring(zone.h)
  if currentLayoutKey ~= key then
    buildLayout()
  end -- Header
  
  -- local nbtn, hasProp = modeToLayout(mode)
  -- local title = "XANYLVGL #"..tostring(id)
  -- local line2
  -- if mode == 4 and zone.w >= 350 and zone.h >= 200 then
    --line2 = buildAnglePropDebugLine()									   
	-- line2 = "CH"..tostring(ch).."  MODE "..tostring(mode).." (ANGLE)+PROP  REPEAT "..tostring(rep)
  -- elseif mode == 4 then
    -- line2 = "CH"..tostring(ch).."  MODE "..tostring(mode).." (ANGLE)+PROP  REPEAT "..tostring(rep)
  -- else
    -- line2 = "CH"..tostring(ch).."  MODE "..tostring(mode).." (SW"..tostring(nbtn)..")"..(hasProp and "+PROP" or "").."  REPEAT "..tostring(rep)
  -- end
  
  local version = (widget.api and widget.api.VERSION) or ""
  if version ~= "" then
    lvgl.label(zone.x + zone.w - 30, zone.y + 4, "v" .. tostring(version), LEFT + SMLSIZE)
  end

  local logoOffset = drawHeaderLogo()
  lvgl.label(zone.x + 2 + logoOffset, zone.y + 1, title, BOLD)
  lvgl.label(zone.x + 2 + logoOffset, zone.y + 16, line2, SMLSIZE)

  if mode == 4 and zone.w >= 350 and zone.h >= 200 then
    drawPods() -- add four pods (ANGLE+PROP plein écran)
  end
  
  -- GUI : on laisse EVT_EXIT_BREAK à EdgeTX (RET)
  gui.run(event, touchState)
end

function widget:background()
  if lvgl then
    return
  end
  -- rien pour l'instant
end

return widget
