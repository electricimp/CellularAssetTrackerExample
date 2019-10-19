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
const MSG_ACK_TIMEOUT = 10;

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

        // Ack report immediately
        local ack = customAck();
        ack();

        if (!("fix" in report) && "cellInfo" in report) {
            // Use cell info from device to get location from 
            // Google maps API
            local cellStatus = loc.parseCellInfo(report.cellInfo);
            if ("cellid" in cellStatus) {
                loc.getLocCellInfo(cellStatus, function(location) {
                    if (location != null) {
                        report.cellInfoLoc <- location;
                    }

                    // Log status report from device
                    printReportData(report);
                    // Send device data to cloud service
                    cloud.send(report);
                }.bindenv(this));
                
                // Let cell location response trigger report send to cloud 
                return;
            }
        } 

        // Log status report from device
        printReportData(report);
        // Send device data to cloud service
        cloud.send(report);
    }

    function getAssist(payload, customAck) {
        local reply = customAck();

        ::debug("[Main] Requesting offline assist messages from u-blox webservice");
        loc.getAssistBinary(function(assistBinary) {
            ::debug("[Main] Received online assist messages from u-blox webservice");
            if (assistBinary != null) {
                ::debug("[Main] Sending device assist binary file");
                reply(assistBinary);
            } else {
                ::debug("[Main] Failed to get assist binary. Sending empty reply to device");
                reply();
            }
        }.bindenv(this))
    }

    function printReportData(report) {
        ::debug("[Main] Recieved status update from device:");
        ::debug("--------------------------------------------------------------");
        ::debug("[Main] Raw report: ");
        ::debug(http.jsonencode(report));

        if ("ts" in report) ::debug("[Main] Report created at: " + formatDate(report.ts));
        if ("secSinceBoot" in report) ::debug("[Main] Report sent " + report.secSinceBoot + "s after device booted");

        ::debug("[Main] Telemetry details: ");
        if ("magnitude" in report)   ::debug("[Main]   Magnitude: "     + report.magnitude   + " Gs");
        if ("accel" in report)       ::debug("[Main]   Accelerometer: " + http.jsonencode(report.accel));
        if ("temperature" in report) ::debug("[Main]   Temperature: "   + report.temperature + "°C");
        if ("humidity" in report)    ::debug("[Main]   Humidity: "      + report.humidity    + "%");

        
        if ("battStatus" in report) { 
            local status = report.battStatus;
            ::debug("[Main] Battery Status details:");
            if ("capacity" in status) ::debug("[Main]   Remaining battery capacity: " + status.capacity + " mAh");
            if ("percent" in status)  ::debug("[Main]   Remaining battery " + status.percent + "%");
        }

        if ("fix" in report) {
            local fix = report.fix;
            ::debug("[Main] Location fix details: ");
            ::debug("[Main]   Fix time " + fix.time);
            ::debug("[Main]   Seconds to first fix: " + fix.secTo1stFix);
            ::debug("[Main]   Seconds to accurate fix: " + fix.secToFix);
            ::debug("[Main]   Fix type: " + getFixDescription(fix.fixType));
            ::debug("[Main]   Fix accuracy: " + fix.accuracy + " meters");
            ::debug("[Main]   Latitude: " + fix.lat + ", Longitude: " + fix.lon);
        }

        if ("cellInfo" in report) {
            ::debug("[Main] Location cell info details: ");
            ::debug("[Main]   Location data not available. Cell info: " + report.cellInfo);
            if ("cellInfoLoc" in report) {
                local loc = report.cellInfoLoc;
                ::debug("[Main]   Fix accuracy: " + loc.accuracy + " meters");
                ::debug("[Main]   Latitude: " + loc.lat + ", Longitude: " + loc.lon);
            }
        }

        if ("movement" in report) ::debug("[Main] Movement detected: " + report.movement);
        ::debug("--------------------------------------------------------------");
    }

    function formatDate(t = null) {
        local d = (t == null) ? date() : date(t);
        return format("%04d-%02d-%02d %02d:%02d:%02d", d.year, (d.month+1), d.day, d.hour, d.min, d.sec);
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
