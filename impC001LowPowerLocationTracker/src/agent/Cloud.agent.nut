// MIT License

 // Copyright 2019 Electric Imp

 // SPDX-License-Identifier: MIT

 // Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

 // The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.

 // THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO
// EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES
// OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
// ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
// OTHER DEALINGS IN THE SOFTWARE.

// Cloud Service File 

const LOSANT_APPLICATION_ID   = "@{LOSANT_APPLICATION_ID}";
const LOSANT_DEVICE_API_TOKEN = "@{LOSANT_DEVICE_API_TOKEN}";

const DEVICE_NAME_TEMPLATE    = "Tracker_%s";
const DEVICE_DESCRIPTION      = "Electric Imp C001 Tracker";
const LOSANT_DEVICE_CLASS     = "standalone";

// Manages Cloud Service Communications  
// Dependencies: YOUR CLOUD SERVICE LIBRARY 
// Initializes: YOUR CLOUD SERVICE LIBRARY
class Cloud {

    _lsnt      = null;
    
    _lsntDevId = null;
    _devId     = null; 
    _agentId   = null;

    constructor() {
        _devId   = imp.configparams.deviceid; 
        _agentId = split(http.agenturl(), "/").top();

        _lsnt = Losant(LOSANT_APPLICATION_ID, LOSANT_DEVICE_API_TOKEN);

        ::debug("[Cloud] Check Losant app for devices with matching tags.");
        getLosantDeviceId();
    }

    function send(report) {
        // Check that we have a Losant device configured
        if (_lsntDevId == null) {
            ::error("[Cloud] Losant device not configured. Cannot send data");
            ::debug(http.jsonencode(report));
            return;
        }

        local payload = {
            "time" : ("ts" in report) ? _lsnt.createIsoTimeStamp(report.ts) : _lsnt.createIsoTimeStamp(),
            "data" : _formatData(report)
        };

        ::debug("[Cloud] Sending device state to Losant");
        ::debug(http.jsonencode(payload));
        _lsnt.sendDeviceState(_lsntDevId, payload, _sendDeviceStateHandler.bindenv(this));
    }

    // Losant Device Management Requests
    // ---------------------------------------------------------------

    function getLosantDeviceId() {
        // Create filter for tags matching this device info,
        // Tags for this app are unique combo of agent and imp device id
        local qparams = _lsnt.createTagFilterQueryParams(createTags());

        // Check if a device with matching unique tags exists, create one
        // and store losant device id.
        _lsnt.getDevices(_getDevicesHandler.bindenv(this), qparams);
    }

    function createDevice() {
        // This should be done with caution, it is possible to create multiple devices
        // Each device will be given a unique Losant device id, but will have same agent
        // and imp device ids

        // Only create if we do not have a Losant device id
        if (_lsntDevId == null) {
            local deviceInfo = {
                "name"        : format(DEVICE_NAME_TEMPLATE, _agentId),
                "description" : DEVICE_DESCRIPTION,
                "deviceClass" : LOSANT_DEVICE_CLASS,
                "tags"        : createTags(),
                "attributes"  : createAttrs()
            }
            ::debug("[Cloud] Sending request to create new device in Losant application");
            _lsnt.createDevice(deviceInfo, _createDeviceHandler.bindenv(this))
        }
    }

    function updateDevice(newAttributes, newTags = null) {
        if (_lsntDevId != null) {
            if (newTags == null) newTags = createTags();
            local deviceInfo = {
                "name"        : format(DEVICE_NAME_TEMPLATE, _agentId),
                "description" : DEVICE_DESCRIPTION,
                "deviceClass" : LOSANT_DEVICE_CLASS,
                "tags"        : newTags,
                "attributes"  : newAttributes
            }
            ::debug("[Cloud] Sending update device info request to Losant");
            _lsnt.updateDeviceInfo(_lsntDevId, deviceInfo, _updateDeviceInfoHadler.bindenv(this))
        } else {
            ::error("[Cloud] Losant device id not retrieved yet. Cannot update device info.");
        }
    }

    // Response Handlers
    // ---------------------------------------------------------------

    function _sendDeviceStateHandler(resp) {
        if (resp.statuscode == 200) {
            ::debug("[Cloud] Report send to Losant successful");
        } else {
            ::error("[Cloud] Report send to Losant failed, status code: " + resp.statuscode);
            ::debug(resp.body);
        }
    }

    function _getDevicesHandler(resp) {
        ::debug("[Cloud] Processing Losant getDevices response, status code: " + resp.statuscode);

        try {
            local body = http.jsondecode(resp.body);
            if (resp.statuscode == 200 && "count" in body) {
                // Successful request
                switch (body.count) {
                    case 0:
                        // No devices found, create device
                        ::debug("[Cloud] Device not found.");
                        createDevice();
                        break;
                    case 1:
                        // We found the device, store the losDevId
                        ::debug("[Cloud] Device with matching tags found.");
                        if ("items" in body && "deviceId" in body.items[0]) {
                            _lsntDevId = body.items[0].deviceId;
                            // Make sure the attributes and tags in Losant
                            // match the current code.
                            updateDevice(createAttrs(), createTags());
                        } else {
                            ::error("[Cloud] Losant device id not in payload.");
                            ::debug("[Cloud] Response " + resp.body);
                        }
                        break;
                    default:
                        // Log results of filtered query
                        ::error("[Cloud] Found " + body.count + " devices matching the device tags.");

                        // TODO: Delete duplicate devices - look into how to determine which device
                        // is active, so data isn't lost
                }
            } else {
                ::error("[Cloud] Losant getDevices request failed with status code: " + res.statuscode);
            }
        } catch(e) {
            ::error("[Cloud] Losant getDevices request parsing error: " + e);
        }
    }

    function _updateDeviceInfoHadler(resp) {
        ::debug("[Cloud] Received update device resopnse from Losant, status code: " + resp.statuscode);
        ::debug(resp.body);
    }

    function _createDeviceHandler(resp) {
        ::debug("[Cloud] Received create device response from Losant, status code: " + resp.statuscode);
        try {
            local body = http.jsondecode(resp.body);
            if ("deviceId" in body) {
                _lsntDevId = body.deviceId;
                ::debug("[Cloud] Losant device created with id: " + _lsntDevId);
            } else {
                ::error("[Cloud] No Losant device id found in response");
                ::debug(resp.body);
            }
        } catch(e) {
            ::error("[Cloud] Error parsing Losant create device response");
        }
    }

    // Device and Data Helpers
    // ---------------------------------------------------------------

    function createTags() {
        return [
            {
                "key"   : "agentId",
                "value" : _agentId
            },
            {
                "key"   : "impDevId",
                "value" : _devId
            },
        ]
    }

    function createAttrs() {
        return [
            {
                "name"     : "locType",
                "dataType" : "string"
            },
            {
                "name"     : "locAccuracy",
                "dataType" : "number"
            },
            {
                "name"     : "location",
                "dataType" : "gps"
            },  
            {
                "name"     : "temperature",
                "dataType" : "number"
            },
            {
                "name"     : "humidity",
                "dataType" : "number"
            }, 
            {
                "name"     : "battery",
                "dataType" : "number"
            },
            {
                "name"     : "magnitude",
                "dataType" : "number"
            },
            {
                "name"     : "movement",
                "dataType" : "boolean"
            }, 
            {
                "name"     : "tempAlert",
                "dataType" : "string"
            },
            {
                "name"     : "humidAlert",
                "dataType" : "string"
            },
            {
                "name"     : "batteryAlert",
                "dataType" : "string"
            },
            {
                "name"     : "impactAlert",
                "dataType" : "string"
            }   
        ];
    }

    function _formatData(data) {
        // Note: Data must match attributes name and data type. 
        local formatted = {};

        if ("temperature" in data) formatted.temperature <- data.temperature;
        if ("humidity" in data)    formatted.humidity    <- data.humidity;
        if ("battStatus" in data)  formatted.battery     <- data.battStatus.percent;
        if ("magnitude" in data)   formatted.magnitude   <- data.magnitude;
        if ("movement" in data)    formatted.movement    <- data.movement;

        if ("fix" in data && "lat" in data.fix && "lon" in data.fix) {
            local fix = data.fix;
            formatted.locType <- "GPS";
            if ("lat" in fix && "lon" in fix) {
                formatted.location <- _formatLocation(fix.lat, fix.lon);
            }
            if ("accuracy" in data.fix) formatted.locAccuracy <- fix.accuracy;
        } else if ("cellInfoLoc" in data) {
            local loc = data.cellInfoLoc;
            formatted.locType <- "GMAPS_API";
            formatted.location <- _formatLocation(loc.lat, loc.lon);
            formatted.locAccuracy <- loc.accuracy;
        }

        // Set Alerts to default message
        local defaultAlertMsg = "No Alert, In Range";
        formatted.tempAlert    <- defaultAlertMsg;
        formatted.humidAlert   <- defaultAlertMsg;
        formatted.batteryAlert <- defaultAlertMsg;
        formatted.impactAlert  <- defaultAlertMsg;

        // Update if Alert condition is active
        if ("alerts" in data && data.alerts.len() > 0) {
            foreach(alert in data.alerts) {
                if (alert.resolved != 0) {
                    switch(alert.type) {
                        case ALERT_TYPE.TEMP_LOW: 
                        case ALERT_TYPE.TEMP_HIGH:
                            formatted.tempAlert = alert.description;
                            break;
                        case ALERT_TYPE.HUMID_LOW:
                        case ALERT_TYPE.HUMID_HIGH: 
                            formatted.humidAlert = alert.description;
                            break;
                        case ALERT_TYPE.BATTERY_LOW: 
                            formatted.batteryAlert = alert.description;
                            break;
                        case ALERT_TYPE.SHOCK:
                            formatted.impactAlert = alert.description;
                            break;
                    }
                }
            }
        } 

        return formatted;
    }

    function _formatLocation(lat, lon) {
        return format("%s,%s", lat, lon);
    }

}
