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

// Device Main Application File

// Libraries
#require "SPIFlashFileSystem.device.lib.nut:2.0.0"
#require "ConnectionManager.lib.nut:3.1.1"
#require "Messenger.lib.nut:0.1.0"
#require "LPDeviceManager.device.lib.nut:0.1.0"
#require "Promise.lib.nut:4.0.0"
// Sensor Libraries
#require "LIS3DH.device.lib.nut:3.0.0"
#require "HTS221.device.lib.nut:2.0.1"
// Battery Charger/Fuel Gauge Libraries
#require "MAX17055.device.lib.nut:1.0.1"
#require "BQ24295.device.lib.nut:1.0.0"

// Supporting files
// NOTE: Order of files matters do NOT change unless you know how it will effect
// the application
@include __PATH__ + "/Hardware.device.nut"
@include __PATH__ + "/../shared/Logger.shared.nut"
@include __PATH__ + "/../shared/Constants.shared.nut"
@include __PATH__ + "/Persist.device.nut"
@include __PATH__ + "/Location.device.nut"
@include __PATH__ + "/Motion.device.nut"
@include __PATH__ + "/Battery.device.nut"
@include __PATH__ + "/Env.device.nut"


// Main Application
// -----------------------------------------------------------------------

// Wake every x seconds to check if report should be sent
const CHECK_IN_TIME_SEC        = 86400; // 60s * 60m * 24h
// Wake every x seconds to send a report, regaurdless of check results
const REPORT_TIME_SEC          = 604800; // 60s * 60m * 24h * 7d
// Maximum time to stay awake
const MAX_WAKE_TIME            = 70;

// Maximum time to wait for GPS to get a fix, before trying to send report
// NOTE: This should be less than the MAX_WAKE_TIME
const LOCATION_TIMEOUT_SEC     = 55;
// Accuracy of GPS fix in meters
const LOCATION_ACCURACY        = 10;

// Force in Gs that will trigger movement interrupt
const MOVEMENT_THRESHOLD       = 0.05;
// Low battery alert threshold in percentage
const BATTERY_THRESH_LOW       = 10;
// Temperature above alert threshold in deg C will trigger alert
const TEMP_THRESHOLD_HIGH      = 30;
// Humidity above alert threshold will trigger alert
const HUMID_THRESHOLD_HIGH     = 90;

// Constant used to validate imp's timestamp
const VALID_TS_YEAR            = 2019;
// Max time to wait for agent/device message ack
const MSG_ACK_TIMEOUT          = 10;


class MainController {

    // Supporting CLasses
    cm            = null;
    msgr          = null;
    lpm           = null;
    move          = null;
    loc           = null;
    persist       = null;

    // Application Variables
    bootTime      = null;
    maxWakeTimer  = null;
    gpsFixTimer   = null;

    // Flags 
    gettingAssist = null;

    constructor() {
        // Get boot timestamp
        bootTime = hardware.millis();

        // Initialize ConnectionManager Library - this sets the connection policy, so divice can
        // run offline code. The connection policy should be one of the first things set when the
        // code starts running.
        // TODO: In production update CM_BLINK to NEVER to conserve battery power
        // TODO: Look into setting connection timeout (currently using default of 60s)
        cm = ConnectionManager({ 
            "blinkupBehavior": CM_BLINK_ALWAYS,
            "retryOnTimeout" : false
        });
        imp.setsendbuffersize(8096);

        // Initialize Logger
        Logger.init(LOG_LEVEL.DEBUG, cm);

        ::debug("--------------------------------------------------------------------------");
        ::debug("[Main] Device started...");
        ::debug(imp.getsoftwareversion());
        ::debug("--------------------------------------------------------------------------");

        // Initialize movement tracker, boolean to configure i2c in Motion constructor
        // NOTE: This does NOT configure/enable/disable movement tracker
        move = Motion(true);

        // Initialize SPI storage class
        persist = Persist();

        // Initialize Low Power Manager Library - this registers callbacks for each of the
        // different wake reasons (ie, onTimer, onInterrupt, defaultOnWake, etc);
        local handlers = {
            "onTimer"       : onScheduledWake.bindenv(this),
            "onInterrupt"   : onMovementWake.bindenv(this),
            "defaultOnWake" : onBoot.bindenv(this)
        }
        lpm = LPDeviceManager(cm, handlers);

        // Set connection callbacks
        cm.onConnect(onConnect.bindenv(this));
        cm.onTimeout(onConnTimeout.bindenv(this));

        // Initialize Messenger for agent/device communication 
        // Defaults: message ackTimeout set to 10s, max num msgs 10, default msg ids
        msgr = Messenger({"ackTimeout" : MSG_ACK_TIMEOUT});
        msgr.onFail(msgrOnFail.bindenv(this));
        msgr.onAck(msgrOnAck.bindenv(this));
    }

    // Msgr handlers
    // -------------------------------------------------------------

    // Global Message Failure handler
    function msgrOnFail(message, reason) {
        // Store message info in variables
        local payload = message.payload;
        local id      = payload.id;
        local name    = payload.name;
        local msgData = payload.data;

        ::error(format("[Main] %s message send failed: %s", name, reason));

        // Handle each type of message failure
        switch(name) {
            case MSG_ASSIST:
                // If first message fails, then don't wait for assist 
                // messages before sleeping.
                gettingAssist = false;
                ::debug(format("Main] Retrying %s message send.", name));
                // Retry message 
                msgr.send(name, msgData);
                break;
            case MSG_REPORT:
                powerDown();
                break;
        }
    }

    function msgrOnAck(message, ackData) {
        // Store message info in variables
        local payload = message.payload;
        local id      = payload.id;
        local name    = payload.name;
        local msgData = payload.data;

        // Handle each type of message failure
        switch(name) {
            case MSG_ASSIST:
                onAssistAck(msgData, ackData);
                break;
            case MSG_REPORT:
                onReportAck(msgData);
                break;
        }
    }

    // Msgr assist messages ACK handler
    function onAssistAck(type, ackData) {
        if (ackData == null) {
            ::debug("[Main] Didn't receive any Assist messages from agent.");
            return;
        }

        // ackData contains assist messages from cloud
        local assistBinary = ackData;
        ::debug("[Main] Recieved assist messages from agent");

        // Write assist messages to GPS module to help get accurate fix more quickly
        loc.writeAssistMsgs(assistBinary, onAssistMsgDone.bindenv(this));
    }

    // Msgr report ACK handler
    function onReportAck(report) {
        // Report successfully sent
        ::debug("[Main] Report ACK received from agent");

        // Movement event reported, clear movement detection flag
        if (persist.getAlert(ALERT_TYPE.MOVEMENT)) {
            // Re-enable movement detection
            move.enable(MOVEMENT_THRESHOLD, onMovement.bindenv(this));
            // Set stored movement flag to false
            persist.setAlert(ALERT_TYPE.MOVEMENT, false);
        }

        // All other alerts should wait until next reading clears them.
        // Report reading values are not persisted, and will be cleared when we sleep

        // NOTE: Reporting is scheduled based purely on REPORT_TIME_SEC, if an alert triggered
        // this report the next report will be scheduled REPORT_TIME_SEC from now
        updateReportingTime();
        powerDown();
    }

    // Connection Handlers
    // -------------------------------------------------------------

    // Connection Flow
    function onConnect() {
        ::debug("[Main] Device connected...");

        // Check if we need to refresh assist binary
        if (shouldGetAssist()) {
            gettingAssist = true;
            // Refresh assist messages
            ::debug("[Main] Requesting GPS assist binary from agent.");
            msgr.send(MSG_ASSIST, null);
        }
    }

    // Connection time-out flow
    function onConnTimeout() {
        ::debug("[Main] Connection try timed out.");
        powerDown();
    }

    // Wake up (not on interrupt or timer) flow
    function onBoot(wakereson) {
        ::debug("[Main] Wake reason: " + lpm.wakeReasonDesc());

        // Set a limit on how long we are awake for, sets a timer that triggers 
        // powerDown/sleep
        setMaxWakeTimeout();

        // Enable movement monitor
        move.enable(MOVEMENT_THRESHOLD, onMovement.bindenv(this));

	    // NOTE: overwriteStoredConnectSettings method persistes the current time as the
        // next check-in and report time. This is only needed if CHECK_IN_TIME_SEC
        // and/or REPORT_TIME_SEC have been changed. Reomove when not in active development. 
        overwriteStoredConnectSettings();

        // Check if report needed or if we are just checking for env/battery alerts 
        shouldReport()
            .then(reportingFlow.bindenv(this), readingFlow.bindenv(this));
    }

    // Wake up on timer flow
    function onScheduledWake() {
        ::debug("[Main] Wake reason: " + lpm.wakeReasonDesc());

        // Set a limit on how long we are awake for, sets a timer that triggers 
        // powerDown/sleep
        setMaxWakeTimeout();

        // Configure Interrupt Wake Pin
        // No need to (re)enable movement detection, these settings
        // are stored in the accelerometer registers. Just need
        // to configure the wake pin.
        move.configIntWake(onMovement.bindenv(this));

        // Check if report needed or if we are just checking for env/battery alerts 
        shouldReport()
            .then(reportingFlow.bindenv(this), readingFlow.bindenv(this));
    }

    // Wake up on interrupt flow
    function onMovementWake() {
        ::debug("[Main] Wake reason: " + lpm.wakeReasonDesc());

        // If event valid, disables movement interrupt and store movement flag
        onMovement();

        // Sleep til next check-in time
        // Note: To conserve battery power, after movement interrupt
        // we are not connecting right away, we will report movement
        // on the next scheduled check-in time
        powerDown();
    }

    // Connection Flow Handlers
    // -------------------------------------------------------------

    function reportingFlow(val) {
        // Note: Task Promises should always resolve, since a rejected promise would 
        // stop other tasks from completing
        local tasks = [getLocation(), getEnvReadings(), getAccelReading(), getBattStatus()];
        Promise.all(tasks).then(onReportingTasksComplete.bindenv(this), onTasksFail.bindenv(this));
    }

    function readingFlow(val) {
        // Note: Task Promises should always resolve, since a rejected promise would 
        // stop other tasks from completing
        local tasks = [getEnvReadings(), getBattStatus()];
        Promise.all(tasks).then(onReadingTasksComplete.bindenv(this), onTasksFail.bindenv(this));
    }

    // Actions that return promises
    // -------------------------------------------------------------

    // Helper to kick off connection asap
    // Returns promise, that checks the connection status, the next scheduled 
    // report time, if the imp has a valid timestamp, and if there are any 
    // conditions stored that need to be reported. The promise should
    // resolve if the reporting flow should be triggered, and reject if no 
    // reporting conditions have been met
    function shouldReport() {
        return Promise(function(resolve, reject) {
            // Resolve - Should connect and send report
            // Reject  - No connection or report needed

            // If we are connected, then resolve immediately to trigger sending report flow
            if (cm.isConnected() || shouldConnect()) {
                // We have a condition that should trigger a report, connect or trigger onConnected
                // handler and resolve immediately to trigger sending report flow
                cm.connect();
                return resolve();
            }

            // No need to trigger reporting flow, Reject with flag indicating if location should be checked
            // before powering down
            return reject();
        }.bindenv(this))
    }

    // Initializes Env Monitor and gets temperature and humidity. Returns a
    // promise that resolves when reading is complete
    function getEnvReadings() {
        // Get temperature and humidity reading
        // NOTE: I2C is configured when Motion class is initailized in the 
        // constructor of this class, so we don't need to configure it here.
        // Initialize Environmental Monitor without configuring i2c
        local env = Env();
        return Promise(function(resolve, reject) {
            env.getTempHumid(function(reading) {
                    ::debug("--------------------------------------------------------------------------");
                    ::debug("[Main] Get temperature and humidity complete:");
                    if ("error" in reading) {
                        ::error("[Main] Reading contained error: " + reading.error);
                        reading = null;
                    }
                    if (reading != null) {
                        ::debug(format("[Main] Current Humidity: %0.2f %s, Current Temperature: %0.2f °C", reading.humidity, "%", reading.temperature));
                        // Update alerts if needed
                        storeEnvAlerts(reading);
                    }
                    ::debug("--------------------------------------------------------------------------");
                    return resolve(reading);
                }.bindenv(this));
        }.bindenv(this))
    }

    // Initializes Battery monitor and gets battery status. Returns a promise
    // that resolves when status has been attained
    function getBattStatus() {
        // NOTE: I2C is configured when Motion class is initailized in the
        // constructor of this class, so we don't need to configure it here.
        // Initialize Battery Monitor without configuring i2c
        local battery = Battery(false);
        return Promise(function(resolve, reject) {
            battery.getStatus(function(status) {
                ::debug("--------------------------------------------------------------------------");
                ::debug("[Main] Get battery status complete:")
                if ("error" in status) {
                    ::error("[Main] Battery status contained error: " + status.error);
                    status = null;
                }
                if ("percent" in status && "capacity" in status) {
                    ::debug("[Main] Remaining cell capacity: " + status.capacity + "mAh");
                    ::debug("[Main] Percent of battery remaining: " + status.percent + "%");
                    ::debug("--------------------------------------------------------------------------");

                    // Update alerts if needed
                    storeBattAlert(status);
                }
                return resolve(status);
            }.bindenv(this));
        }.bindenv(this))
    }

    // Returns a promise that resolves after getting an accelerometer reading
    function getAccelReading() {
        return Promise(function(resolve, reject) {
            move.getAccelReading(function(reading) {
                ::debug("--------------------------------------------------------------------------");
                ::debug("[Main] Get accelerometer reading complete:");
                if ("error" in reading) {
                    ::error("[Main] Reading contained error: " + reading.error);
                    reading = null;
                }
                if (reading != null) {
                    ::debug(format("[Main] Acceleration (G): x = %0.4f, y = %0.4f, z = %0.4f", reading.x, reading.y, reading.z));
                    reading.mag <- move.getMagnitude(reading);
                } 
                ::debug("--------------------------------------------------------------------------");
                return resolve(reading);
            }.bindenv(this));
        }.bindenv(this));
    }

    // Powers up GPS and starts location message filtering for accurate fix.
    // Returns a promise that resolves when either an accurate fix is found, 
    // or the get location timeout has triggered
    function getLocation() {
        return Promise(function(resolve, reject) {
            if (loc == null) loc = Location(bootTime);
            setLocTimeout();
            loc.getLocation(LOCATION_ACCURACY, function(gpsFix) {
                ::debug("[Main] GPS finished location request...");
                cancelLocTimeout();
                ("error" in gpsFix) ? resolve(null) : resolve(gpsFix);
            }.bindenv(this));
        }.bindenv(this));
    }

    // Async Action Handlers 
    // -------------------------------------------------------------
    
    function onAssistMsgDone() {
        ::debug("[Main] Assist messages written to GPS completed.");
        // Assist binary stored, toggle flag that lets device know it is ok to sleep
        gettingAssist = false;
    }

    // Pin state change callback & on wake pin action
    // If event valid, disables movement interrupt and store movement flag
    function onMovement() {
        // Check if movement occurred
        // Note: Motion detected method will clear interrupt when called
        if (move.detected()) {
            ::debug("[Main] Movement event detected");
            // Store movement flag
            persist.setAlert(ALERT_TYPE.MOVEMENT, true);

            // If movement occurred then disable interrupt, so we will not
            // wake again until scheduled check-in time
            move.disable();
        }
    }

    // Triggered during onBoot and onScheduledWake flows when it is
    // determined that a report should be sent and all promise tasks
    // have completed
    function onReportingTasksComplete(taskValues) {
        ::debug("[Main] Reporting Tasks completed");
        // Collect reading values
        local gpsFix        = taskValues[0];
        local envReadings   = taskValues[1];
        local accelReading  = taskValues[2];
        local batteryStatus = taskValues[3];

        // Send report
        ::debug("[Main] Creating report");
        local report = createReport(persist.getAlerts(), envReadings, batteryStatus, accelReading, gpsFix);
        sendReport(report);
    }

    function onReadingTasksComplete(taskValues) {
        ::debug("[Main] Reading Tasks completed");
        // Collect reading values
        local envReadings   = taskValues[0];
        local batteryStatus = taskValues[1];

        // Check for alerts
        local alerts = persist.getAlerts();
        if (alerts != ALERT_TYPE.NONE ) {
            ::debug("[Main] Have conditions to report...");
            // Send report
            local report = createReport(alerts, envReadings, batteryStatus);
            sendReport(report);
        } else {
            ::debug("[Main] No conditions to report, powering down.");
            powerDown();
        }
    }

    function onTasksFail(reason) {
        ::error("[Main] Promise rejected reason: " + reason);
        powerDown();
    }

    // Reporting Helpers
    // -------------------------------------------------------------

    function createReport(alerts, envReadings, battStatus, accelReading = null, gpsFix = null) {
        local report = {
            "secSinceBoot" : (hardware.millis() - bootTime) / 1000.0,
            "ts"           : time()
        }

        if (battStatus != null)   report.battStatus <- battStatus;
        if (accelReading != null) {
            report.accel     <- accelReading;
            report.magnitude <- accelReading.mag;
        }
        if (alerts != null)       report.alerts     <- alerts;

        if (envReadings != null) {
            report.temperature <- envReadings.temperature;
            report.humidity    <- envReadings.humidity;
        }

        if (gpsFix != null) {
            report.fix <- gpsFix;
            report.fix.accuracy <- "Under " + LOCATION_ACCURACY + " meters";
        }

        return report;
    }

    // Helper that checks connection status to either trigger a report send or 
    // schedule a report send. This helper also adds a check to add cellInfo to 
    // the report once the device is connected to the server.
    function sendReport(report) {
        if (!cm.isConnected()) {
            // Schedule a report send on next connect
            cm.onNextConnect(function() {
                // Add cell info if fix is not in report
                ("fix" in report) ? _sendReport(report) : _addCellInfoAndSendReport(report);
            }.bindenv(this));
            // NOTE: Calling connect if we are already trying to connect is ok, since  
            // ConnectionManager library manages this condition
            // Try to connect
            cm.connect();
        } else {
            // Add cell info if fix is not in report
            ("fix" in report) ? _sendReport(report) : _addCellInfoAndSendReport(report);
        }
    }

    // Helper that adds cell info to report then triggers the report send when 
    // info request is completed
    function _addCellInfoAndSendReport(report) {
        imp.net.getcellinfo(function(cellInfo) {
            // Add cell info if fix is not in report
            report.cellInfo <- cellInfo;
            _sendReport(report);
        }.bindenv(this))
    }

    // Helper that sends report to agent
    function _sendReport(report) {
        // MOVEMENT DEBUGGING LOG
        ::debug("[Main] Accel is enabled: " + move._isAccelEnabled() + ", accel int enabled: " + move._isAccelIntEnabled() + ", movement flag: " + (persist.getAlert(ALERT_TYPE.MOVEMENT) == ALERT_TYPE.MOVEMENT));

        // Send to agent
        ::debug("[Main] Sending device status report to agent");
        msgr.send(MSG_REPORT, report);
    }

    // Sleep Management
    // -------------------------------------------------------------

    // Updates report time
    function updateReportingTime() {
        local now = time();

	    // If report timer expired set based on current time offset with by the boot ts
        local reportTime = now + REPORT_TIME_SEC - (bootTime / 1000);

        // Update report time if it has changed
        persist.setReportTime(reportTime);

        ::debug("Next report time " + reportTime + ", in " + (reportTime - now) + "s");
    }

    // Updates check-in time if needed, and returns time in sec to sleep for
    // Optional parameter, a boolean, whether to offset check-in time based on 
    // the time we have been awake
    function getSleepTimer(adjForTimeAwake = false) {
        local now = time();
        // Get stored wake time
        local wakeTime = persist.getWakeTime();

        // Our timer has expired, update it to next interval
        if (wakeTime == null || now >= wakeTime) {
            wakeTime = (adjForTimeAwake) ? (now + CHECK_IN_TIME_SEC - (bootTime / 1000)) : (now + CHECK_IN_TIME_SEC);
            persist.setWakeTime(wakeTime);
        }

        local sleepTime = (wakeTime - now);
        ::debug("[Main] Setting sleep timer: " + sleepTime + "s");
        return sleepTime;
    }

    // Debug logs about how long divice was awake, and puts device to sleep
    function powerDown() {
        // Cancel max wake timer if it is still running
        cancelMaxWakeTimeout();

        // If writing GPS assist messages, wait unitl done before sleeping
        if (gettingAssist == true) {
            imp.wakeup(1, powerDown.bindenv(this));
            return;
        }

        // Log how long we have been awake
        local now = hardware.millis();
        ::debug("Time since code started: " + (now - bootTime) + "ms");
        ::debug("Going to sleep...");

        lpm.sleepFor(getSleepTimer());
    }

    // Timer Helpers
    // -------------------------------------------------------------

    // Creates a timer that powers down GPS power after set time
    function setLocTimeout() {
        // Ensure only one timer is set
        cancelLocTimeout();
        // Start a timer to send report if no GPS fix is found
        gpsFixTimer = imp.wakeup(LOCATION_TIMEOUT_SEC, function() {
            ::debug("[Main] GPS failed to get an accurate fix. Disabling GPS power.");
            loc.disableGNSS();
        }.bindenv(this));
    }

    // Cancels the timer set by setLocTimeout helper
    function cancelLocTimeout() {
        if (gpsFixTimer != null) {
            imp.cancelwakeup(gpsFixTimer);
            gpsFixTimer = null;
        }
    }

    // Sets a timer that triggers powerDown after set time
    function setMaxWakeTimeout() {
        // Ensure only one timer is set
        cancelMaxWakeTimeout();
        // Start a timer to power down after we have been awake for set time
        maxWakeTimer = imp.wakeup(MAX_WAKE_TIME, function() {
            ::debug("[Main] Wake timer expired. Triggering power down...");
            powerDown();
        }.bindenv(this));
    }

    // Cancels the timer set by setMaxWakeTimeout helper
    function cancelMaxWakeTimeout() {
        if (maxWakeTimer != null) {
            imp.cancelwakeup(maxWakeTimer);
            maxWakeTimer = null;
        }
    }

    // Helpers
    // -------------------------------------------------------------

    function storeEnvAlerts(reading) {
        // Store alert state for env readings
        persist.setAlert(ALERT_TYPE.TEMP_HIGH, reading.temperature >= TEMP_THRESHOLD_HIGH);
        persist.setAlert(ALERT_TYPE.HUMID_HIGH, reading.humidity >= HUMID_THRESHOLD_HIGH);
    }

    function storeBattAlert(status) {
        // Store alert state, if battery below expected
        persist.setAlert(ALERT_TYPE.BATT_LOW, status.percent <= BATTERY_THRESH_LOW);
    }

    function shouldGetAssist() {
        if (loc == null) loc = Location(bootTime);
        return !loc.assistIsValid();
    }

    // Returns boolean, checks for event(s) or if report time has passed
    function shouldConnect() {
        // Check for events

        // Note: We are not storing triggering conditions, just an integer 
        // that identifies the alert condition, movement, temp, humid, battery
        local alerts = persist.getAlerts();
        if (alerts != ALERT_TYPE.NONE) {
            ::debug(format("[Main] Alerts detected: 0x%02X", alerts));
            return true;
        }

        // Note: We need a valid timestamp to determine sleep times.
        // If the imp looses all power, a connection to the server is
        // needed to get a valid timestamp.
        local validTS = validTimestamp();
        ::debug("Valid timestamp: " + validTS);
        if (!validTS) return true;

        // Check if report time has passed
        local now = time();
        local shouldReport = (now >= persist.getReportTime());
        ::debug("Time to send report: " + shouldReport);
        return shouldReport;
    }

	// Overwrites currently stored wake and report times
    function overwriteStoredConnectSettings() {
        local now = time();
        persist.setWakeTime(now);
        persist.setReportTime(now);
    }

    // Returns boolean, if the imp module currently has a valid timestamp
    function validTimestamp() {
        local d = date();
        // If imp doesn't have a valid timestamp the date method returns
        // a year of 2000. Check that the year returned by the date method
        // is greater or equal to VALID_TS_YEAR constant.
        return (d.year >= VALID_TS_YEAR);
    }

}

// Runtime
// -----------------------------------------------------------------------

// Start controller
MainController();
