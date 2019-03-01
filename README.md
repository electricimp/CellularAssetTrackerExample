# Low Power Cellular Asset Tracker

## Overview

This is software for a low power cellular asset tracker. The tracker monitors for movement, and if movement has been detected it will report daily, otherwise the device will report once a week sending GPS location, battery status, and movement status. 

## Hardware

impC001 cellular module
impC001 breakout board
u-blox M8N GPS module
[3.7V 2000mAh battery from Adafruit](https://www.adafruit.com/product/2011?gclid=EAIaIQobChMIh7uL6pP83AIVS0sNCh1NNQUsEAQYAiABEgKFA_D_BwE)

## Setup

This project uses u-blox AssistNow services, and requires and account and authorization token from u-blox. To apply for an account register [here](http://www.u-blox.com/services-form.html). 
<br>
<br>
This project has been written using [VS code plug-in](https://github.com/electricimp/vscode). All configuration settings and pre-processed files have been excluded. Follow the instructions [here](https://github.com/electricimp/vscode#installation) to install the plug-in and create a project. 
<br>
<br>
Replace the **src** folder in your newly created project with the found in this repository
<br>
<br>
Update settings/imp.config device_code, agent_code, and builderSettings to the following:

```
    "device_code": "src/device/Main.device.nut"
    "agent_code": "src/agent/Main.agent.nut"
    "builderSettings": {
        "variable_definitions": {
            "UBLOX_ASSISTNOW_TOKEN" : "<YOUR-UBLOX-ASSIST-NOW-TOKEN-HERE>"
        }
    }
```

## Customization

Settings are all stored as constants. Modify to customize the application.