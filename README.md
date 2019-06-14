# Low Power Cellular Asset Tracker 1.0.1 #

## Overview ##

This repo provides software to drive a low-power cellular asset tracker. The tracker monitors for movement; if movement is detected, the tracker will report daily, otherwise the device will report once a week sending GPS location, battery status and movement status.

## Hardware ##

This example requires the following hardware:

- [impC001 cellular module](https://developer.electricimp.com/hardware/imp/datasheets#impc001)
- [impC001 breakout board](https://developer.electricimp.com/hardware/resources/reference-designs/impc001breakout)
- [u-blox M8N GPS module](https://www.u-blox.com/en/product/neo-m8-series)
- [3.7V 2000mAh battery from Adafruit](https://www.adafruit.com/product/2011?gclid=EAIaIQobChMIh7uL6pP83AIVS0sNCh1NNQUsEAQYAiABEgKFA_D_BwE)

## Other Requirements ##

This project uses u-blox AssistNow services, and requires an account and authorization token from u-blox. To apply for an account, please register [here](http://www.u-blox.com/services-form.html).

## Setup ##

This project has been written using [Electric Imp’s plug-in for Microsoft’s VS Code text editor](https://github.com/electricimp/vscode). All configuration settings and pre-processed files have been excluded. Please follow [these instructions](https://github.com/electricimp/vscode#installation) to install the plug-in and create a project.

Replace the `src` folder in your newly created project with the `src` folder found in this repository.

Update settings/imp.config "device_code", "agent_code", and "builderSettings" to the following (updating the UBLOX_ASSISTNOW_TOKEN with your u-blox Assist Now authorization token):

```
    "device_code": "src/device/Main.device.nut"
    "agent_code": "src/agent/Main.agent.nut"
    "builderSettings": {
        "variable_definitions": {
            "UBLOX_ASSISTNOW_TOKEN" : "<YOUR-UBLOX-ASSIST-NOW-TOKEN-HERE>"
        }
    }
```

We recommend that UART logging is enabled during development so that you can see logs from the device even when it is offline. The code uses **hardware.uartDCAB** (Pin A: RTS, Pin B: CTS, Pin C: RX, Pin D: TX) for logging.

## Customization ##

Settings are all stored as constants. Modify these to customize the application to your requirements.

## Measurements ##

Rough wake timings base on code committed on 3/1/18 under good cellular conditions and in a location that can get a GPS fix.

- Wake with no connections: ~650-655 ms
- Wake and connection: ~40s
- Cold boot (connection established before code starts): ~20-30s

## Release Notes ##

- 1.0.1
    - Update `Battery.device.nut` and `Main.device.nut` to support the new [BQ25895 library](https://github.com/electricimp/BQ25895).
- 1.0.0
    - Initial release.

# License #

Code licensed under the [MIT License](LICENSE).