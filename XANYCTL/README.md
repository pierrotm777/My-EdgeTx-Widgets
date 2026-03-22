
# XANYCTL Widget for EdgeTX (Radiomaster TX16S)
This widget uses the RCUL/XANY protocol created by Rc-Navy.  
The RCUL project of Rc-Navy is described [here](http://p.loussouarn.free.fr/arduino/exemple/BURC/BURC.html)  

Many thanks to him !  

## Overview

**XANYCTL** is a touchscreen widget for **EdgeTX** designed to control a **Multiplex XAny encoder** using Lua.  
It provides a graphical interface (buttons + slider) that allows the pilot to control **up to 16 logical switches** and an optional **PROP analog parameter**.

The widget is intended to work with a companion **Mix script** that converts the widget state into a valid **XAny pulse stream** sent on a radio channel.

Typical use case:

TX16S → EdgeTX widget → Lua Mix script → RC channel → receiver → XAny decoder.

The project is composed of two main parts:

* **Widget UI (WIDGETS/XANYCTL)** – graphical interface and state management
* **Mix script (SCRIPTS/MIXES/xanytx.lua)** – XAny protocol generation


---

# Architecture

```
SDCARD/
 ├─ WIDGETS/
 │   └─ XANYCTL/
 │        ├─ main.lua
 │        ├─ buttons.lua
 │        ├─ TEMPLATE.lua
 │        ├─ README.md
 │        ├─ Languages/
 │        │  └─ cn,de,en,fr,it,sp,ua
 │        └─ Images/
 │            └─ all png files
 └─ SCRIPTS/
     └─ MIXES/
          ├─ xanytx.lua
		  ├─ xanytx_common.lua
		  ├─ xanytx1.lua
		  ├─ xanytx2.lua
		  ├─ xanytx3.lua
		  └─ xanytx4.lua
```


## main.lua

This is the **widget entry point**.

Responsibilities:

- Define **widget options**
- Provide the **API used by the UI**
- Store and retrieve values from **EdgeTX Global Variables (GVARS)**
- Initialize the GUI and load configuration

The widget does **not generate XAny frames directly**.  
It only stores user inputs in GVars which are later read by the mix script.



## buttons.lua

Contains the **graphical interface** using **libGUI**.

Features:

- Toggle buttons
- Momentary buttons
- Vertical PROP slider
- Rounded UI elements
- Optional shadows
- Custom ON/OFF colors
- Touch interaction

The UI is intentionally separated from `main.lua` to keep the architecture modular.


## xanytx.lua

Lua **Mix Script** responsible for generating the XAny signal.

Responsibilities:

- Read widget state from **GVars**
- Build the **XAny payload**
- Compute checksum
- Apply **R compression**
- Handle **Repeat**
- Convert nibbles to **EdgeTX pulse widths**
- Output signal on the assigned RC channel



---

# Data Storage (GVars)

The widget uses **EdgeTX Global Variables** to exchange data with the mix script.

| GVar | Purpose |
|-----|--------|
| GV1 | Switch mask (low bits) |
| GV2 | Switch mask (high bits) |
| GV3 | Repeat value |
| GV4 | Mode |
| GV5 | Channel memory |
| GV6 | Motors Synchro |
| GV7 | PROP value (0-255) |
| GV8 | ANGLE value (0-360°) |

# Supported Modes

| Mode | Description |
|-----|-------------|
| 0 | SW8 |
| 1 | SW8 + PROP |
| 2 | SW16 |
| 3 | SW16 + PROP |
| 4 | ANGLE + PROP |


---

# User Interface

The UI uses **libGUI** components:

- Rounded buttons
- Toggle and momentary actions
- Vertical slider
- Customizable colors
- Optional shadows
- Optional Motors Synchro
- Optional languages

The slider controls the **PROP value (0-255)** and displays the percentage.

---

# Installation

## 1. Copy Files

Copy the folders to your **EdgeTX SD card**.

```
SDCARD/WIDGETS/XANYCTL/
SDCARD/SCRIPTS/MIXES/
```


## 2. Add Widget

1. Open your model
2. Go to **Display → Widgets**
3. Select an empty slot
4. Choose **XANYCTL**


## 3. Configure Options

Available widget options:

* ID
* MODE
* CH
* Repeat
* OffCol
* OnCol
* Shadow
* Synchro
* Language

---

## 4. The sesult
Screen two Xany control  
![](TWO_XANYCTL.png)

Screen four Xany control  
![](FOUR_XANYCTL.png)

Screen height buttons  
![](SW8.png)

Screen height buttons and one slider  
![](SW8+PROP.png)

Screen sixteen buttons  
![](SW16.png)

Screen sixteen buttons and one slider   
![](SW16+PROP.png)

Screen Angle and Slider for azimuthal  
![](ANGLE+PROP.png)

# Change labels
You can to adapt labels of 4 instances.  
When the widget is first launched, a Lua file named with the model name, TOTO.lua, is created in the widget folder. 
This file defines the labels for each button or slider, as well as the button type (permanent or momentary).  

```
{ label="Feux mât",  type="toggle" },
{ label="Lumière Cabine",  type="toggle" },
{ label="Lumière intérieure",  type="toggle" },
{ label="Radar",  type="toggle" },
{ label="Sirène",  type="momentary" },
{ label="6",  type="toggle" },
{ label="7",  type="toggle" },
{ label="8",  type="toggle" },
{ label="9",  type="toggle" },
{ label="10", type="toggle" },
{ label="11", type="toggle" },
{ label="12", type="toggle" },
{ label="13", type="toggle" },
{ label="14", type="toggle" },
{ label="15", type="toggle" },
{ label="16", type="toggle" },
```

# Hardware Tested

- Radiomaster **TX16S**
- EdgeTX **2.11.x**
- Multiplex **XAny**
- Custom Arduino **Xany2Spy decoder**

---

# Compatibilities
1. MultiSwitch_Sw16-ProMicro
   * [V1.0](https://github.com/Ingwie/OpenAVRc_Hw/tree/V3/MultiSwitch_Sw16-ProMicro)  
   ![here](https://github.com/Ingwie/OpenAVRc_Hw/blob/V3/MultiSwitch_Sw16-ProMicro/MultiSwitch_Sw16_ProMicro_3D.jpg)  
   
1. MultiSwitch_Sw8 (deprecated)
   * [V1.0](https://github.com/Ingwie/OpenAVRc_Hw/tree/V3/MultiSwitch_Sw8)  
   ![here](https://github.com/Ingwie/OpenAVRc_Hw/blob/V3/MultiSwitch_Sw8/D%C3%A9codeur%20MS8_X-Any_3D.jpg)  
   
1. MultiSwitch_Sw8 V2
   * [V1.2](https://github.com/Ingwie/OpenAVRc_Hw/tree/V3/MutltiSwitch_Sw8_V2)  
   ![here](https://github.com/Ingwie/OpenAVRc_Hw/blob/V3/MultiSwitch_Sw8_V2/MultiSwitch_Sw8_V2.jpg)  
   
1. MultiSwitch_Sw8 V3
   * [V1.3](https://github.com/Ingwie/OpenAVRc_Hw/tree/V3/MultiSwitch_Sw8_V3)  
   ![here](https://github.com/Ingwie/OpenAVRc_Hw/blob/V3/MultiSwitch_Sw8_V3/MultiSwitch_Sw8_V3_Top.png)  
   
1. The MS8-Xany card used as an Impulse Sequencer
   * [V1.0](https://github.com/Ingwie/OpenAVRc_Hw/tree/V3/MultiSwitch_Sw8_PulseSeq)  
   ![here](https://github.com/Ingwie/OpenAVRc_Hw/blob/V3/MultiSwitch_Sw8/D%C3%A9codeur%20MS8_X-Any_3D.jpg)  
   
1. Xany2Msx
   * [V1.0](https://github.com/Ingwie/OpenAVRc_Hw/tree/V3/Xany2Msx)  
   ![here](https://github.com/Ingwie/OpenAVRc_Hw/blob/V3/Xany2Msx/Xany2Msx_3D.jpg)  

1. Capteur_Hall_I2C
   * [V1.0](https://github.com/Ingwie/OpenAVRc_Hw/tree/V3/Capteur_Hall_I2C)  
   ![here](https://github.com/Ingwie/OpenAVRc_Hw/blob/V3/Capteur_Hall_I2C/Sensor_Board_3D.jpg)  
   
1. Capteur_Hall_I2C Mini
   * [V1.0](https://github.com/Ingwie/OpenAVRc_Hw/tree/V3/Capteur_Hall_I2C_Mini)  
   ![here](https://github.com/Ingwie/OpenAVRc_Hw/blob/V3/Capteur_Hall_I2C_Mini/Sensor_Board_3D-Top_Bottom.jpg)  
   
1. Encoder A1335 I2C
   * [V1.0](https://github.com/Ingwie/OpenAVRc_Hw/tree/V3/PCB%20A1335_Encoder)  
   ![here](https://github.com/Ingwie/OpenAVRc_Hw/blob/V3/PCB%20A1335_Encoder/A1335_Encoder_Top.jpg)  

   
1. Xany2Sounds
   * [V1.0](https://github.com/Ingwie/OpenAVRc_Hw/tree/V3/Xany2Sounds)  
   ![here](https://github.com/Ingwie/OpenAVRc_Hw/blob/V3/Xany2Sounds/Xany2Sounds_3D.jpg)  
   
1. Sound&SmokeModule
   * [V1.1](https://github.com/Ingwie/OpenAVRc_Hw/tree/V3/Sound&SmokeModule)  
      ![here](https://github.com/Ingwie/OpenAVRc_Hw/blob/V3/Sound%26SmokeModule/S%26SM1.png)  
	  
1. Futaba FP-S148/S3003 replacement
   * [V1.0](https://github.com/Ingwie/OpenAVRc_Hw/tree/V3/LUCAS_FPS148_FS3003)  
   ![here](https://github.com/Ingwie/OpenAVRc_Hw/blob/V3/LUCAS_FPS148_FS3003/LUCAS_FPS148_FS3003_Top.jpg)  

# Future Work

Planned improvements:

- Multi instances support (up to 4 widgets)
- Improved layout system
- Advanced slider styling
- Optional telemetry feedback



---

# Author

Original concept and testing by the project author.  
Development assistance provided via AI collaboration.

