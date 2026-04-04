# ESPNow RSSI Widget for EdgeTX

## Overview

This widget displays the **RSSI (Received Signal Strength Indicator)** of an ESP-NOW wireless trainer link on an EdgeTX radio.

It is designed to work with a custom ESP32-based system that:
- Transmits control data over ESP-NOW
- Encodes link status and RSSI into **Channel 8 (CH8)**

The widget decodes this information and provides:
- Visual link status
- Real-time RSSI display
- Color-coded signal quality
- Audio alarms based on thresholds and language

---

## System Architecture

### ESP32 Side

The ESP32 encodes:
- **Link state**
- **RSSI (in dBm)**

into CH8 using a custom mapping:

| CH8 (µs) | Meaning |
|----------|--------|
| ~1100    | CONNECTING |
| 1300–2000| CONNECTED + RSSI |

RSSI mapping:
- 1300 → -95 dBm
- 2000 → -45 dBm

The value is then converted to **SBUS raw (0–2047)** before transmission.

---

### EdgeTX Widget

The widget:
1. Reads CH8 using `getValue()`
2. Converts raw SBUS → µs
3. Decodes:
   - Link state
   - RSSI (if connected)

---

## Display Behavior

### CONNECTING
- Display: `---`
- Background: **Red**
- No audio alarms

### CONNECTED
- Displays RSSI in dBm
- Background color based on thresholds:
  - Green → Good signal
  - Yellow → Medium signal
  - Red → Weak signal

---

## Audio Alerts

Audio files are selected automatically based on language:

```
/WIDGETS/EspNow/Langs/<lang>/
```

Required files:
- `yellow.wav`
- `red.wav`

Example:
```
/WIDGETS/EspNow/Langs/fr/yellow.wav
/WIDGETS/EspNow/Langs/fr/red.wav
```

---

## Widget Options

| Option | Description |
|------|------------|
| RssiCh | Channel source (must be CH8) |
| GreenThr | RSSI threshold for green |
| YellowThr | RSSI threshold for yellow |
| AlarmSec | Repeat interval for alarms |
| Language | Language folder for sounds |

---

## Installation

1. Copy the widget folder to:
```
/WIDGETS/EspNow/
```

2. Add language folders:
```
/WIDGETS/EspNow/Langs/en/
/WIDGETS/EspNow/Langs/fr/
...
```

3. Place sound files inside each language folder

4. On EdgeTX:
   - Add widget to screen
   - Set **RssiCh = CH8**

---

## Requirements

- EdgeTX 2.11+
- ESP32 (C3 or S3)
- ESP-NOW wireless trainer system
- SBUS-compatible receiver or virtual SBUS pipeline

---

## Notes

- RSSI accuracy depends on correct SBUS encoding on ESP32 side
- Widget assumes CH8 follows the defined encoding scheme
- If signal remains stuck, verify CH8 updates correctly

---

## Author / Context

This widget was developed for a custom RC system combining:
- ESP32 (ESP-NOW communication)
- EdgeTX radios (TX16S, etc.)
- Wireless trainer mode replacement

---

## Future Improvements

- Link state text localization
- RSSI bar graph display
- Hysteresis for stable color switching
- Additional states (FAILSAFE, LOST)

---

## License

Free to use and modify.
