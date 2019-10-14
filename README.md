# Low Power Cellular Asset Trackers #

This repository contains examples of low power asset tracking applications. 

## [impC001 UltraLowPowerTracker](./impC001UltraLowPowerTracker) ##

This example provides software to drive a low-power cellular asset tracker. The tracker monitors for movement; if movement is detected, the tracker will report daily, otherwise the device will report once a week sending GPS location, battery status and movement status.

## [impC001 LowPowerLocationTracker](./impC001LowPowerLocationTracker) ##

This example provides software to drive a low-power cellular asset tracker. The tracker monitors movement, impact events, temperature, humidity, and battery status. When movement is detected, the tracker will check for an impact event or if the location has changed, and if so then generate a report. The tracker also wakes periodically to take readings. If any readings are determined to be out of range a report will be generated and sent to the cloud. If no out of range readings or location changes are detected the tracker will generate a report based on the application's reporting interval. 

This example also has two additional web service integrations. The cloud service class has been used to integrate with Losant. And in the event that the device cannot obtain a GPS fix, it will use the device's cell info to obtain a location using the Google Maps API.

## impC001 Common Configuration ##

All examples share a common set-up, but run different application code. Follow these steps to configure the tracking application of your choice.

### Hardware ###

All examples are configured for the following hardware:

- [impC001 cellular module](https://developer.electricimp.com/hardware/imp/datasheets#impc001)
- [impC001 breakout board](https://developer.electricimp.com/hardware/resources/reference-designs/impc001breakout)
- [u-blox M8N GPS module](https://www.u-blox.com/en/product/neo-m8-series)
- [3.7V 2000mAh battery from Adafruit](https://www.adafruit.com/product/2011?gclid=EAIaIQobChMIh7uL6pP83AIVS0sNCh1NNQUsEAQYAiABEgKFA_D_BwE)

### Ublox Dependency ###

This project uses u-blox AssistNow services, and requires an account and authorization token from u-blox. To apply for an account, please register [here](http://www.u-blox.com/services-form.html).

### Electric Imp Setup ###

You will also need an Electric Imp account: [register here](https://developer.electricimp.com/impcentrallaunchpoint).

Each project has been written using [Electric Imp’s plug-in for Microsoft’s VS Code text editor](https://github.com/electricimp/vscode). All configuration settings and pre-processed files have been excluded. Please follow [these instructions](https://github.com/electricimp/vscode#installation) to install the plug-in and create a project.

Select the example you wish to use and replace the `src` folder in your newly created project with the `src` folder found in the example's directory.

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

For the *LowPowerLocationTracker* add additional api keys for Losant and Google Maps to the builderSettings variable_definitions: 

```
    "device_code": "src/device/Main.device.nut"
    "agent_code": "src/agent/Main.agent.nut"
    "builderSettings": {
        "variable_definitions": {
            "UBLOX_ASSISTNOW_TOKEN" : "<YOUR-UBLOX-ASSIST-NOW-TOKEN-HERE>", 
            "GOOGLE_MAPS_API_KEY" : "<YOUR-GOOGLE-MAPS-API-KEY-HERE>",
            "LOSANT_APPLICATION_ID" : "<YOUR-LOSANT-APPLICATION-ID-HERE>",
            "LOSANT_DEVICE_API_TOKEN" : "<YOUR-LOSANT-DEVICE-API-TOKEN-HERE>"
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

# License #

Code licensed under the [MIT License](LICENSE).
