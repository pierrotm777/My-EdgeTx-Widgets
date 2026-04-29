-- XANYCTL EdgeTx LUA 
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

-- 0..3 maps to FM0..FM3
-- MODIF: EdgeTX GV1..GV8 (GV6 synchro, GV7 PROP, GV8 ANGLE) uniquement (pack boutons + repeat/mode/prop). Voir en-tête. 
----------------------------------------------------------------------
----------------------------------------------------------------------
-- xanytx.lua v1.17 (SW8 + checksum + Repeat, conforme Xany/RcTxSerial)  -- MODIF
--
-- OBJECTIF :
--   Encoder les états (8 inters pour SW8) dans UNE seule voie, selon le principe Xany :
--     - data = 8 bits (0..255)
--     - checksum = data XOR 0x55
--     - nibbles RAW = data_hi, data_lo, cks_hi, cks_lo
--     - message délimité par Idle I (17) au début et à la fin
--     - compression RcTxSerial : si deux nibbles RAW consécutifs sont identiques, le 2ème devient R (16)
--     - Repeat : chaque symbole déjà déterminé est répété (Repeat+1) fois (Repeat stocké dans GV3)  -- MODIF
--
-- IMPORTANT (EdgeTX GVars) :
--   EdgeTX = GV1..GV9. Le widget packe tout dans GV1..GV8 (GV6 synchro, GV7 PROP, GV8 ANGLE) :
--     * GV1/GV2 : mask 16 bits boutons (1..16)
--     * GV3     : Repeat (0..6)
--     * GV4     : MODE (0..4)
--     * GV5     : CH mémo (info)
--     * GV6     : masque synchro pods
--                 bit0 = POD2 suit POD1
--                 bit1 = POD3 suit POD1
--                 bit2 = POD4 suit POD1
--     * GV7     : PROP (0..255)
--     * GV8     : ANGLE (0..359°)

----------------------------------------------------------------------
----------------------------------------------------------------------

-- IMPORTANT (EdgeTX GVars) :
--   EdgeTX = GV1..GV9. Le widget packe tout dans GV1..GV8 (GV6 synchro, GV7 PROP, GV8 ANGLE) :
--     * GV1/GV2 : mask 16 bits boutons (1..16)
--     * GV3     : Repeat (0..6)
--     * GV4     : MODE (0..3)
--     * GV5     : CH mémo (info)
--     * GV6     : Synchro
--     * GV7     : PROP (0..255)
--     * GV8     : ANGLE (0..255)
----------------------------------------------------------------------

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
-- Attention : les index 17,18,19 utilisés dans ce widget sont
-- des "GVars virtuelles" mappées vers les vraies GVars via gv_get/gv_set.
--

-- Largeur d'impulsion correspondant au nibble 0
-- Xany utilise 1024 µs comme base
local US_BASE = 1024

-- Pas entre deux nibbles
-- 1 nibble = +56 µs
local US_STEP = 56

-- Neutre radio standard
local US_NEUT = 1500

-- Amplitude totale entre neutre et extrémité canal
-- IMPORTANT :
--   +/-114%  ˜ 570 µs
--   +/-116%  ˜ 580 µs
--   +/-125%  = 625 µs
--
-- Ajuster selon tes limites CH8
local FULL_EXCURSION_US = 510  -- MODIF: mode ±100% (1000..2000µs)

-- MODIF v1.16b:
--  - US_IDLE_US permet d'ajuster finement l'impulsion Idle si besoin (en µs).
--    Par défaut: 1024 + 56*17 = 1976 µs.
--    Si tu mesures I trop haut/bas, ajuste par pas de 4 ou 8 µs.
local US_IDLE_US = (US_BASE + US_STEP * 17) - 4 -- baisse I de 4µs (évite les 1980)

-- MODIF: compatibilité bitwise EdgeTX/OpenTX (pas d'opérateurs & | ~ << >>)
-- - Si bit32 est dispo: on l'utilise.
-- - Sinon: on émule en arithmétique (32-bit non signé).
local _bit = bit32  -- peut être nil suivant le build

local function _u32(x)
  x = math.floor(tonumber(x) or 0)
  x = x % 4294967296
  return x
end

local function _band(a, b)
  if _bit then return _bit.band(a, b) end
  a = _u32(a); b = _u32(b)
  local res, bit = 0, 1
  for _ = 1, 32 do
    local aa = a % 2
    local bb = b % 2
    if aa == 1 and bb == 1 then res = res + bit end
    a = (a - aa) / 2
    b = (b - bb) / 2
    bit = bit * 2
  end
  return res
end

local function _bor(a, b)
  if _bit then return _bit.bor(a, b) end
  a = _u32(a); b = _u32(b)
  local res, bit = 0, 1
  for _ = 1, 32 do
    local aa = a % 2
    local bb = b % 2
    if aa == 1 or bb == 1 then res = res + bit end
    a = (a - aa) / 2
    b = (b - bb) / 2
    bit = bit * 2
  end
  return res
end

local function _bxor(a, b)
  if _bit then return _bit.bxor(a, b) end
  a = _u32(a); b = _u32(b)
  local res, bit = 0, 1
  for _ = 1, 32 do
    local aa = a % 2
    local bb = b % 2
    if aa ~= bb then res = res + bit end
    a = (a - aa) / 2
    b = (b - bb) / 2
    bit = bit * 2
  end
  return res
end

local function _lsh(a, n)
  if _bit then return _bit.lshift(a, n) end
  return _u32(_u32(a) * (2 ^ (tonumber(n) or 0)))
end

local function _rsh(a, n)
  if _bit then return _bit.rshift(a, n) end
  return math.floor(_u32(a) / (2 ^ (tonumber(n) or 0)))
end

local function _bnot(a)
  if _bit then return _bit.bnot(a) end
  return 4294967295 - _u32(a)
end

----------------------------------------------------------------------
-- clamp(x, lo, hi)
-- Limite une valeur dans un intervalle
-- Utilisé pour éviter de dépasser -1024 / +1024 côté EdgeTX
----------------------------------------------------------------------
local function clamp(x, lo, hi)
  if x < lo then return lo end
  if x > hi then return hi end
  return x
end


----------------------------------------------------------------------
-- us_to_etx(us)
--
-- Convertit une largeur d'impulsion (µs)
-- en valeur mix EdgeTX (-1024..+1024)
--
-- Relation utilisée :
--   us = 1500 + value * FULL_EXCURSION_US / 1024
--
-- Donc :
--   value = (us - 1500) * 1024 / FULL_EXCURSION_US
--
----------------------------------------------------------------------
local function us_to_etx(us)
  local v = (us - US_NEUT) * 1024 / FULL_EXCURSION_US
  return clamp(v, -1024, 1024)
end


----------------------------------------------------------------------
-- nibble_to_etx(n)
--
-- Convertit un nibble Xany (0..15 ou 17=I)
-- en valeur EdgeTX correspondante
--
-- Largeur calculée :
--   us = US_BASE + US_STEP * n
--
-- Puis conversion en valeur radio.
----------------------------------------------------------------------
local function nibble_to_etx(n)
  -- Convertit un nibble Xany (0..15) ou Idle (I=17) en valeur EdgeTX.
  -- MODIF v1.16c:
  --  - On utilise US_IDLE_US pour que l'Idle soit au plus près de 1976µs.
  if n == NIBBLE_I then
    -- Idle = nibble 17
    return us_to_etx(US_IDLE_US)  -- MODIF v1.16b: idle ajustable
  else
    return us_to_etx(US_BASE + US_STEP * n)
  end
end


----------------------------------------------------------------------
----------------------------------------------------------------------
-- TRAME DYNAMIQUE SW8 (data + checksum)
--
-- Le widget fournit 16 boutons, mais en mode SW8 on utilise seulement les 8 premiers (bits 1..8).
-- data = b1..b8 (b1 = LSB)
-- checksum = data XOR 0x55
--
-- nibbles RAW à transmettre : data_hi, data_lo, cks_hi, cks_lo
-- message final : I, (raw1..raw4 compressés par R si doublon), I
----------------------------------------------------------------------
local NIBBLE_I = 17
local NIBBLE_R = 16

-- Accès GVars réelles (GV1..GV8 (GV6 synchro, GV7 PROP, GV8 ANGLE))
-- IMPORTANT : model.getGlobalVariable() attend des index BASE 0.
-- Donc : GV1->0, GV2->1, GV3->2, GV4->3, GV5->4, GV6->5, GV7->6, GV8->7.
local function gvarGet(gvnum, def, fmIndex)
  local fm = fmIndex
  if fm == nil then fm = FM_INDEX end
  -- Read GVars from the requested Flight Mode bank only.
  -- IMPORTANT:
  --   In this multi-pod project, falling back to the current FM can make
  --   XANY1..XANY4 read the same source and recreate a false synchronization.
  local ok, v = pcall(function() return model.getGlobalVariable(gvnum, fm) end)
  if ok and v ~= nil then return v end
  return def
end

-- mask 16 bits boutons depuis GV1/GV2 (pack)
local function getMask16(fmIndex)
  -- IMPORTANT (widget pack GVars) :
  --   GV1 contient le bas 11 bits (0..2047) mais stocké en biaisé :
  --     GV1 = lo - 1024  -> plage [-1024..1023]
  --   GV2 contient les 5 bits hauts (0..31)
  local lo_enc = gvarGet(0, 0, fmIndex) or 0
  local lo = lo_enc + 1024
  if lo < 0 then lo = 0 end
  if lo > 2047 then lo = 2047 end

  local hi = gvarGet(1, 0, fmIndex) or 0
  if hi < 0 then hi = 0 end
  if hi > 31 then hi = 31 end

  return lo + hi * 2048
end

-- Repeat depuis GV3 (0..6)
local function getRepeat(fmIndex)
  local r = gvarGet(2, 0, fmIndex) or 0
  if r < 0 then r = 0 end
  if r > 6 then r = 6 end
  return r
end

-- ----------------------------------------------------------------------
-- Synchro multi-pods
--
-- Mapping réel du projet :
--   GV6 = masque de synchro
--     bit0 = POD2 suit POD1
--     bit1 = POD3 suit POD1
--     bit2 = POD4 suit POD1
--   GV7 = PROP  (0..255)
--   GV8 = ANGLE (0..359°)
--
-- Mapping des Flight Modes / IDs :
--   FM0 = ID1 (maître)
--   FM1 = ID2
--   FM2 = ID3
--   FM3 = ID4
-- ----------------------------------------------------------------------

local function gvarGetFromFM(gvnum, fmIndex, def)
  local ok, v = pcall(function() return model.getGlobalVariable(gvnum, fmIndex) end)
  if ok and v ~= nil then return v end
  return def
end

local function getSyncMask()
  -- IMPORTANT :
  -- Le masque de synchro doit être lu uniquement dans la banque maître FM0.
  -- Sinon un ancien masque conservé dans FM1/FM2/FM3 peut maintenir une
  -- synchro alors que le bouton SYNCHRO du POD1 est sur OFF.
  local m = gvarGetFromFM(5, 0, 0) or 0
  if m < 0 then m = 0 end
  if m > 7 then m = 7 end
  return m
end

local function getModeFromFM(fmIndex)
  -- IMPORTANT :
  -- Le widget principal stocke MODE dans GV4, donc index API EdgeTX = 3.
  -- Si on lit la mauvaise GVar ici, un pod peut être considéré à tort
  -- en ANGLE+PROP et donc rester synchronisé alors qu'il ne devrait pas l'être.
  local mode = gvarGetFromFM(3, fmIndex, 0) or 0
  if mode < 0 then mode = 0 end
  if mode > 4 then mode = 4 end
  return mode
end

local function isSlaveSyncedToMaster(fmIndex)
  -- TEST TEMPORAIRE :
  -- désactive complètement la synchro logique côté mix afin de vérifier
  -- que chaque pod relit bien uniquement son propre FM.
  -- local mask = getSyncMask()

  -- if fmIndex == 0 then
    -- return false
  -- end

  -- -- IMPORTANT :
  -- -- Pas de masque global -> pas de synchro réelle.
  -- if mask == 0 then
    -- return false
  -- end

  -- -- La synchro moteur ne concerne que ANGLE+PROP.
  -- if getModeFromFM(0) ~= 4 then
    -- return false
  -- end
  -- if getModeFromFM(fmIndex) ~= 4 then
    -- return false
  -- end

  -- if fmIndex == 1 then
    -- return _band(mask, 0x01) ~= 0
  -- elseif fmIndex == 2 then
    -- return _band(mask, 0x02) ~= 0
  -- elseif fmIndex == 3 then
    -- return _band(mask, 0x04) ~= 0
  -- end
  return false
end

local function getEffectiveProp(fmIndex)
  local fm = isSlaveSyncedToMaster(fmIndex) and 0 or fmIndex
  local prop = gvarGetFromFM(6, fm, 0) or 0
  if prop < 0 then prop = 0 end
  if prop > 255 then prop = 255 end
  return prop
end

local function getAngle12(fmIndex)
  local fm = isSlaveSyncedToMaster(fmIndex) and 0 or fmIndex
  local a = gvarGetFromFM(7, fm, 0) or 0
  if a < 0 then a = 0 end
  if a > 359 then a = 359 end

  local a12 = math.floor((a * 4095 / 359) + 0.5)
  if a12 < 0 then a12 = 0 end
  if a12 > 4095 then a12 = 4095 end
  return a12
end

-- ----------------------------------------------------------------------
-- build_payload_and_checksum(mode)
--
-- Construit la liste d'octets "data" selon le MODE choisi par le widget,
-- puis calcule le checksum Xany :
--   checksum = XOR( tous les octets de data ) XOR 0x55
--
-- MODE (GV4) :
--   0 = SW8
--   1 = SW8 + PROP
--   2 = SW16
--   3 = SW16 + PROP
--
-- GVars (réelles) utilisées :
--   GV1 + GV2 : mask 16 bits (boutons 1..16)
--   GV7       : PROP (0..255) (uniquement utile en modes +PROP)
--   GV8       : ANGLE (0..359°) utilisé en mode ANGLE+PROP
--   GV6       : masque synchro pods pour recopier PROP/ANGLE de FM0 vers FM1..FM3
-- ----------------------------------------------------------------------
local function build_payload_and_checksum(mode, fmIndex)
  local mask = getMask16(fmIndex)

  -- Octets data[] construits selon le mode
  local data = {}


  -- IMPORTANT :
  --   Pour les modes +PROP, Xany2Spy attend PROP EN PREMIER, puis les boutons.
  --   On construit donc data[] dans cet ordre :
  --     SW8+PROP  : PROP, SW8
  --     SW16+PROP : PROP, SW16 high, SW16 low
  --
  --   Les modes SW8 / SW16 simples restent inchangés.
  if mode == 1 or mode == 3 then
    -- +PROP : ajoute l'octet PROP en premier
    local prop = getEffectiveProp(fmIndex)
    data[#data + 1] = _band(prop, 0xFF)
  end

  if mode == 0 or mode == 1 then
    -- SW8 : pas d'inversion logique des 8 bits boutons
    local mask8 = _band(mask, 0xFF)
    data[#data + 1] = mask8
  else
    -- SW16 : pas d'inversion logique des 16 bits boutons
    local mask16 = _band(mask, 0xFFFF)
    data[#data + 1] = _band(_rsh(mask16, 8), 0xFF)      -- high byte (boutons 9..16)
    data[#data + 1] = _band(mask16, 0xFF)               -- low byte  (boutons 1..8)
  end

  -- Checksum = XOR(data bytes) XOR 0x55
  local cks = 0
  for i = 1, #data do
    cks = _bxor(cks, _band(data[i], 0xFF))
  end
  cks = _bxor(cks, 0x55)
  cks = _band(cks, 0xFF)

  return data, cks
end

-- ----------------------------------------------------------------------
-- build_raw_nibbles()
--
-- Construit la liste des nibbles RAW à transmettre (SANS les Idle I de début/fin).
-- Ordre demandé :
--   SW8        : dhi, dlo, chi, clo
--   SW16       : d0hi, d0lo, d1hi, d1lo, chi, clo
--   SW8+PROP   : d0hi, d0lo, p0hi, p0lo, chi, clo
--   SW16+PROP  : d0hi, d0lo, d1hi, d1lo, p0hi, p0lo, chi, clo
-- ----------------------------------------------------------------------
local function build_raw_nibbles(fmIndex)
  local mode = gvarGet(3, 0, fmIndex) or 0
  if mode < 0 then mode = 0 end
  if mode > 4 then mode = 4 end

  -- --------------------------------------------------------------------
  -- MODIF ANGLE+PROP :
  --   Payload nibble format expected by XanySpy when ANGLE=1 and PROP=1:
  --     a11 a7 a3 p7 p3  (5 nibbles total)
  --
  --   Receiver-side reconstruction:
  --     Angle = (RxMsg[0] << 4) + (RxMsg[1] >> 4)
  --     Prop  = ((RxMsg[1] & 0x0F) << 4) | ((RxMsg[2] & 0xF0) >> 4)
  --
  --   Checksum rule for odd nibble count (per RcRxSerial::msgChecksumIsValid):
  --     checksum = byte0 XOR byte1 XOR (n5 << 4) XOR 0x55
  -- --------------------------------------------------------------------
  if mode == 4 then
    local angle12 = getAngle12(fmIndex)
    local prop = getEffectiveProp(fmIndex)

    local a11 = _band(_rsh(angle12, 8), 0x0F)
    local a7  = _band(_rsh(angle12, 4), 0x0F)
    local a3  = _band(angle12, 0x0F)
    local p7  = _band(_rsh(prop, 4), 0x0F)
    local p3  = _band(prop, 0x0F)

    local raw = { a11, a7, a3, p7, p3 }

    local byte0 = _bor(_lsh(a11, 4), a7)
    local byte1 = _bor(_lsh(a3, 4), p7)
    local byte2_hi = _lsh(p3, 4)

    local cks = 0
    cks = _bxor(cks, _band(byte0, 0xFF))
    cks = _bxor(cks, _band(byte1, 0xFF))
    cks = _bxor(cks, _band(byte2_hi, 0xF0))
    cks = _bxor(cks, 0x55)
    cks = _band(cks, 0xFF)

    raw[#raw + 1] = _band(_rsh(cks, 4), 0x0F)
    raw[#raw + 1] = _band(cks, 0x0F)

    return raw
  end

  local data, cks = build_payload_and_checksum(mode, fmIndex)

  local raw = {}

  -- Data nibbles (hi,lo) pour chaque octet
  for i = 1, #data do
    local b = _band(data[i], 0xFF)
    raw[#raw + 1] = _band(_rsh(b, 4), 0x0F)
    raw[#raw + 1] = _band(b, 0x0F)
  end

  -- Checksum nibbles (hi,lo)
  raw[#raw + 1] = _band(_rsh(cks, 4), 0x0F)
  raw[#raw + 1] = _band(cks, 0x0F)

  return raw
end

-- ----------------------------------------------------------------------
-- Variables d'état (machine d'émission)
--
-- Une machine d'émission indépendante par pod / FM :
--   FM0 -> XANY1
--   FM1 -> XANY2
--   FM2 -> XANY3
--   FM3 -> XANY4
-- On émet une trame :
--   I, RAW..., I
--
-- Compression "R" :
--   - appliquée UNIQUEMENT sur les nibbles RAW consécutifs (pas sur I)
--   - si deux nibbles RAW consécutifs sont identiques, le 2ème devient R (16)
--
-- Repeat (GV3) :
--   - répète le symbole déjà déterminé (RAW ou R) (Repeat+1) fois																				
-- ----------------------------------------------------------------------
local podState = {}
  for i = 0, 3 do
    podState[i] = {
    raw = {},			-- nibbles RAW (sans I)
    rawPos = 0,			-- 0 = on va émettre I de début, 1..#raw = RAW, #raw+1 = I de fin
    lastT = 0,
    stepEvery = 2,		-- 20ms par symbole (tick=10ms)-- 20ms par symbole (tick=10ms)
    lastRaw = -1,		-- dernier nibble RAW (pour compression R)
    lastWasR = false,	-- MODIF v1.3: évite 'R R R' sur longues répétitions (stabilise tout-off)
    txSym = nil,		-- symbole réellement envoyé (RAW ou R ou I)
    repeatCnt = 0,		-- compteur de répétition du txSym
-- Repeat \"par trame\" (option B): réémet la trame complète I..RAW..I, sans allonger la trame.
-- Avantage: compatible décodeurs à longueur stricte (XanySpy/RcRxSerial).
    frameRepLeft = 0,	-- nb de réémissions restantes pour la trame courante
    reuseFrame = false,	-- true => renvoyer le même RAW sans recalcul \(GVars gelées\)
    interIdleLeft = 0,	-- nb de symboles Idle à insérer entre deux trames répétées (stabilité décodeur)
  }
end

local INTER_IDLE_SYMS = 2 -- MODIF: 2 Idles entre trames répétées (ne change pas la longueur payload)

local function initOne(fmIndex)
  local st = podState[fmIndex]
  st.raw = {}
  st.rawPos = 0
  st.lastRaw = -1
  st.lastWasR = false
  -- MODIF v1.2: cadence symbole adaptée quand Repeat>0
  -- Beaucoup de récepteurs sortent la PWM autour de 18ms (≈55Hz). Si on change de symbole
  -- toutes les 20ms (tick=2), le décodeur (RcRxSerial + filtrage) peut voir des transitions
  -- "trop rapides" et perdre la synchro, surtout sur des trames longues (SW16).
  -- => Quand Repeat est actif, on ralentit volontairement la cadence symbole:
  --    - SW8 / SW8+PROP : 30ms (stepEvery=3)
  --    - SW16 / SW16+PROP : 40ms (stepEvery=4)
  --    - Repeat=0 : on conserve 20ms (stepEvery=2) comme avant.							   
  local mode = gvarGet(3, 0, fmIndex) or 0
  if mode < 0 then mode = 0 end
  if mode > 4 then mode = 4 end
  local rep = getRepeat(fmIndex) or 0
  if rep > 0 then
    if mode == 2 or mode == 3 then
      st.stepEvery = 4
    else
      st.stepEvery = 3
    end
  else
    st.stepEvery = 2
  end
  st.txSym = nil
  st.repeatCnt = 0
  st.lastT = getTime()
  st.frameRepLeft = 0
  st.reuseFrame = false
  st.interIdleLeft = 0
end

local function init()
  for fmIndex = 0, 3 do
    initOne(fmIndex)
  end
end

local function refresh_frame(fmIndex)
  local st = podState[fmIndex]
  st.raw = build_raw_nibbles(fmIndex)
  st.rawPos = 0
  st.lastRaw = -1
  -- Option B: Repeat \"par trame\". On gèle le payload au début de la trame,
  -- puis on réémet exactement la même trame frameRepLeft fois après l'Idle de fin.
  st.frameRepLeft = getRepeat(fmIndex) or 0
  st.reuseFrame = false
  st.interIdleLeft = 0
end

local function runOne(fmIndex)
  local st = podState[fmIndex]
  local now = getTime()

  -- Resync si gros trou (radio en attente, etc.)			  
  if st.lastT ~= 0 and (now - st.lastT) > (st.stepEvery * 12) then
    st.rawPos = 0
    st.lastRaw = -1
    st.txSym = nil
    st.lastWasR = false
    st.repeatCnt = 0
    st.lastT = now
    st.frameRepLeft = 0
    st.reuseFrame = false
    st.interIdleLeft = 0
  end

  -- Tant que l'intervalle n'est pas atteint, on maintient le dernier symbole
  if (now - st.lastT) < st.stepEvery then
    return nibble_to_etx(st.txSym or NIBBLE_I)
  end
  st.lastT = now
  -- Option B (Repeat par trame): pas de répétition "symbole par symbole" ici.
  -- La trame complète sera réémise après l'Idle de fin (voir plus bas).
  -- Début d'un nouveau message : on (re)calcule RAW avant d'envoyer le I de début
  if st.rawPos == 0 then
    -- MODIF: entre deux trames répétées, on insère quelques Idles pour fiabiliser le décodeur.
    if st.interIdleLeft > 0 then
      st.interIdleLeft = st.interIdleLeft - 1
      st.txSym = NIBBLE_I
      return nibble_to_etx(st.txSym)
    end
    -- Début de trame: on ne recalcule RAW que si on n'est pas en réémission.
    if not st.reuseFrame then
      refresh_frame(fmIndex)
    else
      -- Réémission: on garde le même RAW (GVars gelées sur la trame précédente).
      st.reuseFrame = false
      st.rawPos = 0
      st.lastRaw = -1
    end
    st.txSym = NIBBLE_I
    st.rawPos = 1
    return nibble_to_etx(st.txSym)
  end

  -- Emission des RAW (compression R uniquement sur RAW)
  if st.rawPos >= 1 and st.rawPos <= #st.raw then
    local r = st.raw[st.rawPos]

    -- MODIF v1.3:
    --   La règle X-Any est "A A -> A R" (compression par paires).
    --   Sur une longue suite identique (ex: 0 0 0 0), il faut obtenir :
    --     0 R 0 R
    --   et non :
    --     0 R R R
    --   Car des symboles identiques consécutifs (R R) deviennent invisibles sur une sortie PWM (~18ms)
    --   et le décodeur peut "perdre des nibbles", surtout quand tous les boutons sont OFF.
    if r == st.lastRaw then
      if st.lastWasR then
        st.txSym = r          -- alterne: ... R, puis RAW
        st.lastWasR = false
      else
        st.txSym = NIBBLE_R   -- alterne: RAW, puis R
        st.lastWasR = true
      end
    else
      st.txSym = r
      st.lastWasR = false
    end

    st.lastRaw = r
    st.rawPos = st.rawPos + 1
    return nibble_to_etx(st.txSym)
  end

  -- Fin de message : I de fin.
  st.txSym = NIBBLE_I
  -- Option B (Repeat par trame): après l'Idle de fin, on réémet la même trame complète.
  if st.frameRepLeft > 0 then
    st.frameRepLeft = st.frameRepLeft - 1
    st.reuseFrame = true
    st.interIdleLeft = INTER_IDLE_SYMS
  end

  st.rawPos = 0
  st.lastRaw = -1
  st.lastWasR = false
  return nibble_to_etx(st.txSym)
end

local function run(event)
  return runOne(0), runOne(1), runOne(2), runOne(3)
end

return {
  input = {},
  output = { "XANY1", "XANY2", "XANY3", "XANY4" },
  run = run,
  init = init
}