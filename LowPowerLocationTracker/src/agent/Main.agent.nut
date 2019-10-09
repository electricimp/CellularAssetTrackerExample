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

// Agent Main Application File

// Libraries 
#require "Messenger.lib.nut:0.1.0"
#require "UBloxAssistNow.agent.lib.nut:1.0.0"
#require "GoogleMaps.agent.lib.nut:1.0.1" 
// TODO: ADD YOUR CLOUD SERVICE LIBRARY HERE

// Supporting files
@include __PATH__ + "/../shared/Logger.shared.nut"
@include __PATH__ + "/../shared/Constants.shared.nut"
@include __PATH__ + "/Location.agent.nut"
@include __PATH__ + "/Cloud.agent.nut"


// Main Application
// -----------------------------------------------------------------------

// Max time to wait for agent/device message ack
const MSG_ACK_TIMEOUT          = 10;

class MainController {
    
    loc   = null;
    msgr  = null;
    cloud = null;

    constructor() {
        // Initialize Logger 
        Logger.init(LOG_LEVEL.DEBUG);

        ::debug("[Main] Agent started...");

        // Initialize Assist Now Location Helper
        loc = Location();

        // Initialize Messenger for agent/device communication 
        // Defaults: message ackTimeout set to 10s, max num msgs 10, default msg ids
        msgr = Messenger({"ackTimeout" : MSG_ACK_TIMEOUT});

        // Open listeners for messages from device
        msgr.on(MSG_REPORT, processReport.bindenv(this));
        msgr.on(MSG_ASSIST, getAssist.bindenv(this));

        // Initialize Cloud Service
        // NOTE: Cloud service class is empty and will initialize an empty framework 
        cloud = Cloud();
    }

    function processReport(payload, customAck) {
        local report = payload.data;

        // Log status report from device
        ::debug("[Main] Recieved status update from device: ");
        ::debug("--------------------------------------------------------------");
        ::debug(http.jsonencode(report));

        if ("fix" in report) {
            local fix = report.fix;
            ::debug("[Main] Location details: ");
            ::debug("[Main] Fix time " + fix.time);
            ::debug("[Main] Seconds to first fix: " + fix.secTo1stFix);
            ::debug("[Main] Seconds to accurate fix: " + fix.secToFix);
            ::debug("[Main] Fix type: " + getFixDescription(fix.fixType));
            ::debug("[Main] Fix accuracy: " + fix.accuracy + " meters");
            ::debug("[Main] Latitude: " + fix.lat + ", Longitude: " + fix.lon);
        }
        ::debug("--------------------------------------------------------------");

        // Send device data to cloud service
        cloud.send(report);
    }

    function getAssist(payload, customAck) {
        local reply = customAck();

        switch (payload.data) {
            case ASSIST_TYPE.OFFLINE:
                ::debug("[Main] Requesting offline assist messages from u-blox webservice");
                loc.getOfflineAssist(function(assistMsgs) {
                    ::debug("[Main] Received online assist messages from u-blox webservice");
                    if (assistMsgs != null) {
                        ::debug("[Main] Sending device offline assist messages");
                        reply(assistMsgs);
                    }
                }.bindenv(this))
                break;
            case ASSIST_TYPE.ONLINE:
                ::debug("[Main] Requesting online assist messages from u-blox webservice");
                loc.getOnlineAssist(function(assistMsgs) {
                    ::debug("[Main] Received online assist messages from u-blox webservice");
                    if (assistMsgs != null) {
                        ::debug("[Main] Sending device online assist messages");
                        reply(assistMsgs);
                    }
                }.bindenv(this))
                break;
            default: 
                ::error("[Main] Unknown assist request from device: " + payload.data);
        }


    }

    function getFixDescription(fixType) {
        switch(fixType) {
            case 0:
                return "no fix";
            case 1:
                return "dead reckoning only";
            case 2:
                return "2D fix";
            case 3:
                return "3D fix";
            case 4:
                return "GNSS plus dead reckoning combined";
            case 5:
                return "time-only fix";
            default: 
                return "unknown";
        }
    }

}

// Runtime
// -----------------------------------------------------------------------

// Start controller
MainController();
