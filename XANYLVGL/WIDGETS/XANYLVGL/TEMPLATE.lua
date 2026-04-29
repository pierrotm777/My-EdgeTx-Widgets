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

-- XANYCTL - configuration par modèle
-- Renommer ce fichier avec le nom exact du modèle EdgeTX (ex: MODEL011.lua ou "MonPlaneur.lua")
--
-- buttons[i] :
--   label = texte affiché
--   type  = "toggle" ou "momentary"
--   logo  = nom du fichier image placé dans /WIDGETS/XANYCTL/Images/
--           Exemple : logo = "MonLogo.png"
--           Laisser "" si aucun logo
--
-- title :
--   titre affiché pour l'instance
--
-- prop :
--   label = texte affiché au-dessus du slider (modes +PROP)

local cfg = {}

cfg.instances = {
  [1] = {
    title = "INSTANCE 1",
    buttons = {
      { label="1",  type="toggle",    logo="" },
      { label="2",  type="toggle",    logo="" },
      { label="3",  type="toggle",    logo="" },
      { label="4",  type="toggle",    logo="" },
      { label="5",  type="toggle",    logo="" },
      { label="6",  type="toggle",    logo="" },
      { label="7",  type="toggle",    logo="" },
      { label="8",  type="toggle",    logo="" },
      { label="9",  type="toggle",    logo="" },
      { label="10", type="toggle",    logo="" },
      { label="11", type="toggle",    logo="" },
      { label="12", type="toggle",    logo="" },
      { label="13", type="toggle",    logo="" },
      { label="14", type="toggle",    logo="" },
      { label="15", type="toggle",    logo="" },
      { label="16", type="toggle",    logo="" },
    },
    prop = { label = "PROP 1", logo="" },
  },

  [2] = {
    title = "INSTANCE 2",
    buttons = {
      { label="1",  type="toggle",    logo="" },
      { label="2",  type="toggle",    logo="" },
      { label="3",  type="toggle",    logo="" },
      { label="4",  type="toggle",    logo="" },
      { label="5",  type="toggle",    logo="" },
      { label="6",  type="toggle",    logo="" },
      { label="7",  type="toggle",    logo="" },
      { label="8",  type="toggle",    logo="" },
      { label="9",  type="toggle",    logo="" },
      { label="10", type="toggle",    logo="" },
      { label="11", type="toggle",    logo="" },
      { label="12", type="toggle",    logo="" },
      { label="13", type="toggle",    logo="" },
      { label="14", type="toggle",    logo="" },
      { label="15", type="toggle",    logo="" },
      { label="16", type="toggle",    logo="" },
    },
    prop = { label = "PROP 2", logo="" },
  },

  [3] = {
    title = "INSTANCE 3",
    buttons = {
      { label="1",  type="toggle",    logo="" },
      { label="2",  type="toggle",    logo="" },
      { label="3",  type="toggle",    logo="" },
      { label="4",  type="toggle",    logo="" },
      { label="5",  type="toggle",    logo="" },
      { label="6",  type="toggle",    logo="" },
      { label="7",  type="toggle",    logo="" },
      { label="8",  type="toggle",    logo="" },
      { label="9",  type="toggle",    logo="" },
      { label="10", type="toggle",    logo="" },
      { label="11", type="toggle",    logo="" },
      { label="12", type="toggle",    logo="" },
      { label="13", type="toggle",    logo="" },
      { label="14", type="toggle",    logo="" },
      { label="15", type="toggle",    logo="" },
      { label="16", type="toggle",    logo="" },
    },
    prop = { label = "PROP 3", logo="" },
  },

  [4] = {
    title = "INSTANCE 4",
    buttons = {
      { label="1",  type="toggle",    logo="" },
      { label="2",  type="toggle",    logo="" },
      { label="3",  type="toggle",    logo="" },
      { label="4",  type="toggle",    logo="" },
      { label="5",  type="toggle",    logo="" },
      { label="6",  type="toggle",    logo="" },
      { label="7",  type="toggle",    logo="" },
      { label="8",  type="toggle",    logo="" },
      { label="9",  type="toggle",    logo="" },
      { label="10", type="toggle",    logo="" },
      { label="11", type="toggle",    logo="" },
      { label="12", type="toggle",    logo="" },
      { label="13", type="toggle",    logo="" },
      { label="14", type="toggle",    logo="" },
      { label="15", type="toggle",    logo="" },
      { label="16", type="toggle",    logo="" },
    },
    prop = { label = "PROP 4", logo="" },
  },
}

return cfg
