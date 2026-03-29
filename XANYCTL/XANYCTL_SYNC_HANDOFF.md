# XANYCTL Project Handoff — Sync Work Preparation

## Purpose of this document

This file summarizes the current state of the project so a new chat can start directly on the **synchronization feature** without losing context.

The project is currently working well on **TX16S 480x272**.  
The next task is to implement **SYNC between widget instances**.

---

# 1. Current project status

## Widget
The widget is named **XANYCTL** and runs on **EdgeTX**.

It currently supports:

- `SW8`
- `SW8+PROP`
- `SW16`
- `SW16+PROP`
- `ANGLE+PROP`

## Current UI state
The current `buttons.lua` version is considered the latest valid base.

Important validated UI points:

- compact mode for non-fullscreen zones
- compact text layout:
  - `XANYCTL #ID`
  - `MODE: ...`
  - `CHANNEL: ...`
- compact layout is left-aligned
- compact layout can display a logo on the left
- full-page mode shows the full UI
- `ANGLE+PROP` screen is visually validated
- dial is centered
- slider remains on the right
- button `ZERO` is placed on the left side
- button `SYNCHRO` exists above `ZERO`
- angle value rectangle has already been reduced and validated

## Current synchronization state
For now:

- the `SYNCHRO` button exists visually
- its state is only local/visual
- the real synchronization logic between IDs is **not yet implemented**

---

# 2. Files and their roles

## `/WIDGETS/XANYCTL/main.lua`
Main widget file.

Responsibilities:

- widget options
- model configuration loading
- language loading
- GVar access wrappers
- API passed to `buttons.lua`
- instance handling through Flight Mode banks

This file should remain stable as much as possible.

## `/WIDGETS/XANYCTL/buttons.lua`
UI and touch interaction file.

Responsibilities:

- buttons
- prop slider
- ANGLE+PROP page
- compact zone display
- logo display
- `ZERO` button
- `SYNCHRO` button (currently visual only)

This is the main file to modify for SYNC UI behavior.

## `/SCRIPTS/MIXES/xanytx.lua`
Mix script entry point.

Used on the output channel.

## `/SCRIPTS/MIXES/xanytx_common.lua`
Core XAny frame generation.

Responsibilities:

- read GVars
- build payload
- checksum
- compression
- repeat
- pulse generation

This file already supports `ANGLE+PROP`.

 `/SCRIPTS/MIXES/xanytx1.lua`
 `/SCRIPTS/MIXES/xanytx2.lua`
 `/SCRIPTS/MIXES/xanytx3.lua`
 `/SCRIPTS/MIXES/xanytx4.lua`

Instance-specific mix scripts mapped to different Flight Mode GVar banks.

---

# 3. Flight Mode / instance architecture

The project uses **Flight Mode GVar banks** to store independent widget states.

Mapping:

| Widget ID | Flight Mode bank |
|---|---|
| 1 | FM0 |
| 2 | FM1 |
| 3 | FM2 |
| 4 | FM3 |

Important:

- widgets do **not** switch the active flight mode
- they only read/write the corresponding GVar bank

This architecture is already working.

---

# 4. Current GVar usage

Current project mapping:

| GVar | Usage |
|---|---|
| GV1 | switch mask low |
| GV2 | switch mask high |
| GV3 | Repeat |
| GV4 | MODE |
| GV5 | channel memory |
| GV6 | currently free / available for sync use |
| GV7 | PROP |
| GV8 | ANGLE |

Important:
- `ANGLE+PROP` is already working correctly
- angle currently uses **GV8**
- prop uses **GV7**

---

# 5. Compact mode choice that must be kept

The preferred compact zone display is:

```lua
if zone.w < 350 or zone.h < 200 then
  local id = (self.options and self.options.ID) or 1
  local ch = (self.options and self.options.CH) or 8
  local mode = normalizeModeChoice((self.options and self.options.MODE) or 0)

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

  lcd.drawText(zone.x + 5, zone.y + zone.h/6 , "XANYCTL " .. "#" .. tostring(id), LEFT + MIDSIZE)
  lcd.drawText(zone.x + 5, zone.y + 55 , "MODE: " .. tostring(modeText), LEFT + SMLSIZE)
  lcd.drawText(zone.x + 5, zone.y + 72 , "CHANNEL: " .. tostring(ch), LEFT + SMLSIZE)
  return
end
```

This layout was explicitly chosen and should be preserved.

---

# 6. Logo usage

Two logo sizes are intended:

- full-page/header logo: `RCUL30x39.png`
- compact zone logo: `RCUL50x68.png`

Compact view uses the larger left-side logo.  
Full-page/header keeps the smaller logo.

---

# 7. Current ANGLE+PROP UI state

Validated points:

- dial centered on the page
- slider remains on the right
- `ZERO` is on the left
- `SYNCHRO` button above `ZERO`
- dial styling is nautical/instrument-like
- dial background is black
- degree text is white
- angle value rectangle is now smaller
- nothing else should be changed unless necessary

---

# 8. Goal for the next chat: implement SYNC

## Target behavior

The user wants the following behavior:

- 4 widget instances may exist at the same time for the same model
- each instance has its own ID and its own output channel
- if `SYNCHRO` is activated on widget **ID1**, then widgets **ID2, ID3, ID4** can be controlled by widget 1
- widgets linked to ID1 should report that they are connected
- only the master widget should command the others
- the master should display green logos indicating which IDs are connected

## Refined target behavior

The preferred concept is now:

- **ID1 is the master**
- `SYNCHRO` is activated from ID1
- there will be an additional selection such as **SYNCHRO FOR**
- this option is only meaningful/accessible for **ID1**
- IDs 2, 3 and 4 become slaves when linked
- slave widgets display a green logo + the master ID
- master widget displays one, two or three green logos depending on how many IDs are connected

## Important UI note
The user explicitly wants:

- `ZERO` kept on the left
- `SYNCHRO` above `ZERO`
- future sync UI should build from this layout

---

# 9. Suggested technical direction for SYNC

A good candidate is to use **GV6**, because it is currently unused.

Possible use:

- `GV6 = 0` → standalone
- `GV6 = 1` → synced to ID1

Possible future extension:

- `GV6 = 1..4` could indicate which master controls the widget

For now, since the user wants ID1 as master, the simplest path is:

- use `GV6` as sync state / link state
- ID1 writes to the banks of ID2 / ID3 / ID4
- slaves read their own banks as usual
- UI decides if they are master/slave based on sync state

---

# 10. Work to produce in the new chat

The next chat should focus on the **real sync implementation**, not on redesigning the widget.

Expected tasks:

## Step 1 — define sync state storage
- use `GV6` for synchronization state
- define exact coding

## Step 2 — add sync behavior in widget logic
- if ID1 is sync master, replicate values to selected IDs
- synchronize:
  - buttons
  - prop
  - angle
  - zero action

## Step 3 — slave mode behavior
- widgets ID2/3/4 should become read-only when controlled by ID1
- slaves should still display their state

## Step 4 — connection indicators
- green logos/icons on slaves
- green logos/icons on master showing how many IDs are linked

## Step 5 — add “SYNCHRO FOR”
- only relevant for ID1
- choose which IDs are controlled

---

# 11. Important instructions for the next chat

Please follow these rules strictly:

1. **Always use the files uploaded in the current chat**
2. **Do not reuse older code from memory**
3. **Keep file order unchanged**
4. **Modify only what is necessary**
5. **Do not rewrite validated code**
6. **UI layout already validated must be preserved**
7. **ANGLE+PROP is already working and should not be broken**

---

# 12. Practical note for the next chat

Start by asking for or using the latest versions of:

- `buttons.lua`
- `main.lua`

Then implement synchronization incrementally, starting from those exact files.

---

End of handoff.
