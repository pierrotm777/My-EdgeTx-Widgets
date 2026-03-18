# mahRe3  
This EdgeTx widget is based on the RCdiy widget, subsequently corrected by Dean Church, Dave Eccleston and then by David Morrison.  
This mahRe3 version is compatible with EdgeTx 2.11 and above.  

## EdgeTX Widget for Voltage and Current Telemetry

--  License  https://www.gnu.org/licenses/gpl-3.0.en.html  
--  OpenTX Lua script  
--  TELEMETRY  

--  File Locations On The Transmitter's SD Card  
/WIDGETS/mahRe3/                               
--  This script file  
/WIDGETS/mahRe3/sounds/  --  Sound files  

--  Works On EdgeTX Version:  2.11 or newer  
--  Works With Sensor: FrSky FAS40S, FCS-150A, FAS100, FLVS Voltage Sensors  

--  Author:  RCdiy  
--  Date:  2016 June 28  
--  Update:  2017 March 27  
--  Reauthored:  Dean Church  --  Date:  2017 March 25  --  Thanks:  TrueBuild  (ideas)  
--  Update:  2019 November 21 by Dave Eccleston  (Handles sensors returning a table of cell voltages)  
--  Update:  2022 December 1 by David Morrison  (Converted to OpenTX Widget for Horus and TX16S radios)  

--  Update: 2026 March 14 by Pierre Montet  
    EdgeTX 2.11+ version (10 options supported)  
    Removed Global Variable dependency (GV6–GV9)  
    RemainingMAH / RemainingPercent converted to BOOL options  
    Reset switch detection improved  

## Changes/Additions:  

  Choose between using consumption sensor or voltage sensor to calculate  

 - battery capacity remaining.  
 - Choose between simple and detailed display.  
 - Voice announcements of percentage remaining during active use  
 - After reset, warn if battery is not fully charged  
 - After reset, check cells to verify that they are within VoltageDelta of each other  
 - Notify if the number of cells falls below the value set in the widget configuration  
 - Show current/low voltage, per cell, in full screen widget  
 - Show current/high Amps in full screen widget  
 - Show current/high Watts in full screen widget  


## Description  
  Reads telemetry sensors to determine battery capacity in mAh  

 - The sensors used are configurable  
 - Reads a battery consumption sensor and/or a voltage sensor to estimate mAh and  %  battery capacity remaining  
 - A consumption sensor is a calculated sensor based on a current sensor and the time elapsed.  http://rcdiy.ca/calculated-sensor-consumption/  
 - Displays remaining battery mAh and percent based on mAh used  
 - Displays battery voltage and remaining percent based on volts    
 - Announces percentage remaining every 10%  change   
     - Announcements are optional,  off by default  
 - Reserve Percentage    
     - All values are calculated with reference to this reserve.    
     - %  Remaining  =  Estimated  %  Remaining  -  Reserve  %    
     - mAh Remaining  =  Calculated mAh Remaining  -  (Size mAh x Reserve  %)    
     - The reserve is configurable,  20%  is the set default    
 - The following is an example of what is dislayed at start up  --  800mAh remaining for a 1000mAh battery    
     - 80%  remaining  

## Notes & Suggestions  

Widget configuration replaces the previous use of OpenTX global variables.  

| Parameter | Use |  
|--|--|  
| NumberCells | Number of Cells In Lipo |  
| LipoCapacity | Lipo Capacity / 100 |  
| RemainingMAH | Enable writing/display of remaining mAh |  
| RemainingPercent | Enable writing/display of remaining bat percentage |  

## Configurations  

 - For help using telemetry scripts  --  http://rcdiy.ca/telemetry-scripts-getting-started/  

If using a current sensor to calculate mAh used then an additional sensor will need to be created to add the values collected from the Curr sensor.  
Create a sensor with the following settings:  

| Field | Value |  
|--|--|  
| Name | mAh |  
| Type | Calculated |  
| Formula | Consumption |  
| Sensor | Curr |  

 - The following additional configurations are available within the script  

| Variable | Use |  
|--|--|  
| VoltageSensor | The name of the voltage sensor in the model configuration |  
| mAhSensor | The name of the mAh sensor in the model configuration |  
| CurrentSensor | The name of the Current sensor in the model configuration |  
| CapacityReservePercent | The battery capacity reserve, set to 0 to disable |  
| SwReset| The switch assigned to reset all values back to defaults |  
| CellFullVoltage| The value of individual cell voltage when the pack is considered full (default is 4.0v) |  
| VoltageDelta | The delta value used to alert when cells are too far out of sync |  
| soundDirPath | The path to the directory where the sound files are located |  
| AnnouncePercentRemaining | Play the percent remaining every 10 percent |  
| SillyStuff | Play some silly/fun sounds |  

1. Define a new sensor **mAh**  
   ![mAh Sensor setup](docs/mAhRe2_mAh_sensor.png)  
2. Defines settings  
   ![Settings](docs/mAhRe2_settings1.png)  
   ![Settings](docs/mAhRe2_settings2.png)  
3. Widget full screen  
![Full screen widget](docs/mAhRe3_full_screen.png)  
4. Widget quarter screen
![Quarter screen widget](docs/mAhRe2_quarter.png)  




