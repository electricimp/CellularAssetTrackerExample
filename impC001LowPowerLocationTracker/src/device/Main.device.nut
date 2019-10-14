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
// GPS Libraries
#require "UBloxM8N.device.lib.nut:1.0.1"
#require "UbxMsgParser.lib.nut:2.0.0"
#require "UBloxAssistNow.device.lib.nut:0.1.0"
// Sensor Libraries
#require "LIS3DH.device.lib.nut:3.0.0"
#require "HTS221.device.lib.nut:2.0.1"
// Battery Charger/Fuel Gauge Libraries
#require "MAX17055.device.lib.nut:1.0.1"
#require "BQ25895.device.lib.nut:3.0.0"

// Supporting files
// NOTE: Order of files matters do NOT change unless you know how it will effect
// the application
@include __PATH__ + "/Hardware.device.nut"
@include __PATH__ + "/../shared/Logger.shared.nut"
@include __PATH__ + "/../shared/Constants.shared.nut"
@include __PATH__ + "/Persist.device.nut"
@include __PATH__ + "/Alerts.device.nut"
@include __PATH__ + "/Location.device.nut"
@include __PATH__ + "/Motion.device.nut"
@include __PATH__ + "/Battery.device.nut"
@include __PATH__ + "/Env.device.nut"

// Main Application
// -----------------------------------------------------------------------

// Wake every x seconds to check sensors for alert conditions. Sleep time 
// is base on this interval. If you wish to extend battery life adjust to 
// a longer interval
const CHECK_IN_TIME            = 60;
// Send a report, regaurdless of check/alert conditions. Update the this to 
// 86400 (one day) after testing completed if you wish to extend battery life
const REPORT_TIME_SEC          = 1800 
// NOTE: Maximum time to stay awake (Must be greater than LOCATION_TIMEOUT_SEC) if 
// you wish to report location. Currently set to (LOCATION_TIMEOUT_SEC + MSG_ACK_TIMEOUT)
const MAX_WAKE_TIME            = 70;

// Maximum time to wait for GPS to get a fix, before trying to send report
// NOTE: This should be less than the MAX_WAKE_TIME
const LOCATION_TIMEOUT_SEC     = 60; 
// Accuracy of GPS fix in meters. GPS will be powered off when this value is met.
// (Location data will only be accurate to this value, so GPS_FILTER and
//  DISTANCE_THRESHOLD_M should be based on this value)
const LOCATION_ACCURACY        = 10;
// Accuracy of GPS fix in meters. If fix did not meet LOCATION_ACCURACY, but did
// meet LOCATION_REPORT_ACCURACY, add it to report anyway.
const LOCATION_REPORT_ACCURACY = 15;
// Distance threshold in meters (30M, ~100ft)
const DISTANCE_THRESHOLD_M     = 30;
// GPS can sometimes jump around when sitting still, use this filter to eliminate 
// small jumps while in the same location. This will also limit the number of 
// times we calculate distance.
const GPS_FILTER               = 0.00015;

// Force in Gs that will trigger movement interrupt
const MOVEMENT_THRESHOLD       = 0.05;
// Low battery alert threshold in percentage
const BATTERY_THRESH_LOW       = 10;
// Temperature above alert threshold in deg C will trigger alert
const TEMP_THRESHOLD_HIGH      = 30;
// Temperature below alert threshold in deg C will trigger alert
const TEMP_THRESHOLD_LOW       = 5;
// Humidity above alert threshold will trigger alert
const HUMID_THRESHOLD_HIGH     = 90;
// Humidity below alert threshold will trigger alert
const HUMID_THRESHOLD_LOW      = 0;
// Force in Gs that will trigger impact alert
const IMPACT_THRESHOLD         = 2.5;

// Limit requests to UBlox Offline assist 
// From datasheet - data updated every 12/24h (12 * 60 * 60 = 43200) 
const OFFLINE_ASSIST_REQ_MAX   = 43200; 
// Constant used to validate imp's timestamp
const VALID_TS_YEAR            = 2019;
// Max time to wait for agent/device message ack
const MSG_ACK_TIMEOUT          = 10;


class MainController {

    // Supporting CLasses
    cm                   = null;
    msgr                 = null;
    lpm                  = null;
    move                 = null;
    loc                  = null;
    persist              = null;

    // Application Variables
    bootTime             = null;
    gpsFixTimer          = null;
    maxWakeTimer         = null;

    // Flags 
    haveAccFix           = null;
    gettingOfflineAssist = null;

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
        
        // Configure Power Gate pin to disabled state
        PWR_GATE_EN.configure(DIGITAL_OUT, 0);

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

        // Set tracking flag defaults
        gettingOfflineAssist = false;
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
                // If first message fails, then don't wait for offline 
                // messages before sleeping.
                if (msgData == ASSIST_TYPE.OFFLINE) gettingOfflineAssist = false;
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
        local assistMsgs = ackData;

        if (type == ASSIST_TYPE.OFFLINE) {
            ::debug("[Main] Offline assist messages received from agent");

            // Store all offline assist messages by date
            persist.storeAssist(ackData);
            // Update time we last checked
            persist.setOfflineAssistChecked(time());
            // Offline assist messages stored, toggle flag that lets device know 
            // if is clear to sleep
            gettingOfflineAssist = false;

            // Get today's date string/file name
            local todayFileName = Location.getAssistDateFileName();
            // Select today's offline assist messages only
            if (todayFileName in ackData) {
                assistMsgs = ackData.todayFileName;
                ::debug("[Main] Writing offline assist messages to u-blox");
            } else {
                ::debug("[Main] No offline assist messges for today. No messages written to UBLOX.");
                return;
            }
        } else {
            ::debug("[Main] Online assist messages received from agent. Writing to u-blox");
        }

        // If GPS is still powered, write assist messages to UBLOX module to help get accurate fix more quickly
        if (PWR_GATE_EN.read() && loc) loc.writeAssistMsgs(assistMsgs, onAssistMsgDone.bindenv(this));
    }

    // Msgr report ACK handler
    function onReportAck(report) {
        // Report successfully sent
        ::debug("[Main] Report ACK received from agent");

        // Movement event reported, clear movement detection flag
        if (persist.getMoveDetected()) {
            // Toggle stored movement flag
            persist.setMoveDetected(false);
        }

        // Toggle all alert reported flags to true
        clearAlerts();

        // Update last reported lat & lon for calculating distance
        if ("fix" in report && "rawLat" in report.fix && "rawLon" in report.fix) {
            local fix = report.fix;
            persist.setLocation(fix.rawLat, fix.rawLon);
        }

        // All other report values are not persisted and so will be reset when we 
        // power down.

        // NOTE: Reporting is scheduled based purely on interval, if movement caused 
        // report the next report will be scheduled based on when that report was sent
        updateReportingTime();
        powerDown();
    }

    // Connection Handlers
    // -------------------------------------------------------------

    // Connection Flow
    function onConnect() {
        ::debug("[Main] Device connected...");

        if (shouldGetOfflineAssist()) {
            gettingOfflineAssist = true;
            // Refresh offline assist messages
            ::debug("[Main] Requesting offline assist messages from agent/Assist Now.");
            msgr.send(MSG_ASSIST, ASSIST_TYPE.OFFLINE);
        }

        // Note: We are only checking for GPS fix, The assumption is that an accurate GPS fix will
        // take longer than getting battery status, env readings etc.
        // haveAccFix flag states: 
            // null  = not looking for location, 
            // false = getting location/but not complete,
            // true  = getting location & have an accurate fix 
        if (haveAccFix == false) {
            // We don't have a fix, request assist online data
            ::debug("[Main] Requesting online assist messages from agent/Assist Now.");
            msgr.send(MSG_ASSIST, ASSIST_TYPE.ONLINE);
        }
    }

    // Connection time-out flow
    function onConnTimeout() {
        ::debug("[Main] Connection try timed out.");
        powerDown();
    }

    // Wake up flow - triggered on all connects except interrupt or timer
    function onBoot(wakereson) {
        ::debug("[Main] Wake reason: " + lpm.wakeReasonDesc());

        // Set a limit on how long we are awake for, sets a timer that triggers 
        // powerDown/sleep
        setMaxWakeTimeout();

	    // NOTE: overwriteStoredConnectSettings method persistes the current time as the
        // next check-in and report time. This is only needed if CHECK_IN_TIME_SEC
        // and/or REPORT_TIME_SEC have been changed. Reomove when not in active development. 
        overwriteStoredConnectSettings();

        // Enable movement monitor
        move.enable(MOVEMENT_THRESHOLD, true, onMovePinStateChange.bindenv(this));

        // Check if report needed or if we are just checking for env/battery alerts 
        shouldReport()
            .then(reportingFlow.bindenv(this), alertCheckFlow.bindenv(this));
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
        move.configIntWake(onMovePinStateChange.bindenv(this));

        // Check if report needed or if we are just checking for env/battery alerts 
        shouldReport()
            .then(reportingFlow.bindenv(this), alertCheckFlow.bindenv(this));
    }

    // Wake up on interrupt flow
    function onMovementWake() {
        ::debug("[Main] Wake reason: " + lpm.wakeReasonDesc());

        // Set a limit on how long we are awake for, sets a timer that triggers 
        // powerDown/sleep
        setMaxWakeTimeout();

        // This releases int pin if it is latched
        local moved = move.detected();
        // Set movement flag if needed
        if (moved) persist.setMoveDetected(true);

        // Configure Interrupt Wake Pin, set impact thresholds and state change callback 
        // while awake, then update to movement before we go back to sleep. This is reset
        // to a movement interrupt during power down.
        // NOTE: Subtract 1G from impact threshold to compensate for HPF 
        move.enMotionDetect(IMPACT_THRESHOLD - 1, ACCEL_IMPACT_INT_DURATION, onImpactPinStateChange.bindenv(this));

        // Check for impact event
        local impactAlert = checkImpact();
        (impactAlert == null && !moved) ? powerDown() : movementCheckFlow(impactAlert);
    }

    // Connection Flow Handlers
    // -------------------------------------------------------------

    function reportingFlow(val) {
        // Note: Task Promises should always resolve, since a rejected promise would 
        // stop other tasks from completing
        local tasks = [getLocation(), getEnvReadings(), getAccelReading(), getBattStatus()];
        Promise.all(tasks).then(onReportingTasksComplete.bindenv(this), onTasksFail.bindenv(this));
    }

    function alertCheckFlow(shouldGetLocation) {
        // Note: Task Promises should always resolve, since a rejected promise would 
        // stop other tasks from completing
        if (shouldGetLocation) {
            local tasks = [getLocation(), getEnvReadings(), getAccelReading(), getBattStatus()];
            Promise.all(tasks).then(onAlertCheckLocTasksComplete.bindenv(this), onTasksFail.bindenv(this));
        } else {
            local tasks = [getEnvReadings(), getBattStatus()];
            Promise.all(tasks).then(onAlertCheckTasksComplete.bindenv(this), onTasksFail.bindenv(this));
        }
    }

    function movementCheckFlow(impactAlert) {
        // Get location and calculate distance to see if we have moved 
        local tasks = [getLocation(), getEnvReadings(), getBattStatus()];
        Promise.all(tasks)
            .then(function(taskValues) {
                onMovementCheckTasksComplete(taskValues, impactAlert);
            }.bindenv(this), onTasksFail.bindenv(this))
    }

    // Async Action Handlers
    // -------------------------------------------------------------

    // Triggered when awake and impact interrupt conditions met
    function onImpactPinStateChange() {
        if (ACCEL_INT.read == 0) return;
        ::debug("[Main] In impact interrupt pin state change callback");

        // Shouldn't need this, but doesn't hurt to trigger
        // just in case. Set movement flag to true
        persist.setMoveDetected(true);

        // Check for impact event. Updates stored alerts if needed
        checkImpact();
    }

    // Triggered when awake and movemnt interrupt conditions met
    function onMovePinStateChange() {
        if (ACCEL_INT.read == 0) return;
        ::debug("[Main] In movement interrupt pin state change callback");

        // Checks for movement, this releases int pin if it is latched.
        local moved = move.detected();
        // Set movement flag if needed (use to indicate that we should check location??)
        if (moved) persist.setMoveDetected(true);

        // Configure Interrupt Wake Pin, set impact thresholds and state change callback 
        // while awake, then update to movement before we go back to sleep. Power down 
        // method resets this to movement detection before sleep.
        // NOTE: Subtract 1G from impact threshold to compensate for HPF 
        move.enMotionDetect(IMPACT_THRESHOLD - 1, ACCEL_IMPACT_INT_DURATION, onImpactPinStateChange.bindenv(this));

        // Check for impact event 
        local impactAlert = checkImpact();

        // If we are already getting location or if no movement or impact detected then
        // don't do anything more
        local gettingLoc = areGettingLocation();
        if (gettingLoc || (!moved && impactAlert == null)) return;

        // NOTE: 
        // If report is already in flight then stored alerts will be caught at next check-in
        // If we are currently getting a location but have not yet received a fix the persisted
        // movement flag will trigger a distance calculation before report is sent. 

        // Not currently checking for a location
        if (!gettingLoc) {
            // Reset wake time to allow for getting location
            cancelMaxWakeTimeout();
            setMaxWakeTimeout();

            // Trigger get location/check distance and schedule report if needed
            movementCheckFlow(impactAlert);
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
        local distance      = null; 

        // Only calculate distance if we have moved
        if (persist.getMoveDetected()) distance = checkDistance(gpsFix);

        // Send report
        ::debug("[Main] Creating report");
        local report = createReport(persist.getAlerts(), envReadings, batteryStatus, accelReading, gpsFix, distance);
        sendReport(report);
    }

    // Triggered during onMovementWake and onMovePinStateChange flows when
    // movement has been detected and all promise tasks have completed
    function onMovementCheckTasksComplete(taskValues, impactAlert) {
        ::debug("[Main] Movement Check Tasks completed");
        
        // Collect reading values
        local gpsFix          = taskValues[0];
        local envReadings     = taskValues[1];
        local batteryStatus   = taskValues[2];
        local accelReading    = (impactAlert != null) ? impactAlert.magnitude : null;

        // Calculate if we have moved a significant distance
        local distance = checkDistance(gpsFix);
        
        // Check for unreported alerts
        local alerts = persist.getAlerts();
        local havePendingAlerts = AlertManager.checkForUnreported(alerts);

        if (havePendingAlerts || distance != null) {
            ::debug("[Main] Have conditions to report...");
            // Send report
            local report = createReport(alerts, envReadings, batteryStatus, accelReading, gpsFix, distance);
            sendReport(report);
        } else {
            ::debug("[Main] No conditions to report, powering down.");
            powerDown();
        }
    }

    // Triggered during onBoot and onScheduledWake flows when it is
    // determined that no report conditions have been met yet, it is
    // determined that location should be checked, and all
    // promise tasks have completed
    function onAlertCheckLocTasksComplete(taskValues) {
        ::debug("[Main] Alert Check Get Location Tasks completed");
        // Collect reading values
        local gpsFix        = taskValues[0];
        local envReadings   = taskValues[1];
        local accelReading  = taskValues[2];
        local batteryStatus = taskValues[3];
 
        // Only calculate distance if we have moved
        local distance = null;
        if (persist.getMoveDetected()) distance = checkDistance(gpsFix);

        // Check for unreported alerts
        local alerts = persist.getAlerts();
        local havePendingAlerts = AlertManager.checkForUnreported(alerts);

        if (havePendingAlerts || distance != null) {
            ::debug("[Main] Have conditions to report...");
            local report = createReport(alerts, envReadings, batteryStatus, accelReading, gpsFix, distance);
            sendReport(report);
        } else {
            ::debug("[Main] No conditions to report, powering down.");
            powerDown();
        }
    }

    // Triggered during onBoot and onScheduledWake flows when it is
    // determined that no report conditions have been met yet, it is
    // determined that location should NOT be checked, and all
    // promise tasks have completed
    function onAlertCheckTasksComplete(taskValues) {
        ::debug("[Main] Alert Check No Location Tasks completed");
        // Offline flow, check readings for alert conditions
        local envReadings   = taskValues[0];
        local batteryStatus = taskValues[1];

        // Check for unreported alerts
        local alerts = persist.getAlerts();
        local havePendingAlerts = AlertManager.checkForUnreported(alerts);

        if (havePendingAlerts) {
            ::debug("[Main] Have conditions to report...");
            local report = createReport(alerts, envReadings, batteryStatus);
            sendReport(report);
        } else {
            ::debug("[Main] No conditions to report, powering down.");
            powerDown();
        }
    }

    // Triggered if an error occured while processing a promise
    function onTasksFail(reason) {
        ::error("[Main] Promise rejected reason: " + reason);
        powerDown();
    }

    // Stores fix data, and powers down the GPS
    function onAccFix(gpxFix, resolve, reject) {
        // We got a fix, cancel timer to send report automatically
        cancelLocTimeout();

        ::debug("[Main] Got accurate fix. Disabling GPS power");
        PWR_GATE_EN.write(0);
        
        // Return fix via promise
        return resolve(gpxFix);
    }

    // Assist messages written to u-blox completed
    // Logs write errors if any
    function onAssistMsgDone(errs) {
        ::debug("[Main] Assist messages written to u-blox");
        if (errs != null) {
            foreach(err in errs) {
                // Log errors encountered
                ::error(err.error);
            }
        }
    }

    // Actions That Return Promises
    // -------------------------------------------------------------

    // Helper to kick off connection asap
    // Returns promise, that checks the connection status, the next scheduled 
    // report time, and if the imp has a valid timestamp. The promise should
    // resolve if the reporting flow should be triggered, and reject if no 
    // reporting conditions have been met
    function shouldReport() {
        return Promise(function(resolve, reject) {
            // Resolve - Should connect/send report
            // Reject  - No connection/report needed, pass boolean if we should get location

            // If we are connected, then resolve immediately to trigger sending report flow
            if (cm.isConnected()) return resolve();

            // We should report if any of the following conditions exists
            if (persist.getReportTime() <= time() || !validTimestamp() || persist.getLocation() == null ||
                AlertManager.checkForUnreported(persist.getAlerts())) {
                    // We have a condition that should trigger a report, connect and 
                    // resolve immediately to trigger sending report flow
                    cm.connect();
                    return resolve();
            }

            // No need to trigger reporting flow, Reject with flag indicating if location should be checked
            // before powering down
            return reject(persist.getMoveDetected());
        }.bindenv(this))
    }

    // Powers up GPS and starts location message filtering for accurate fix.
    // Returns a promise that resolves when either an accurate fix is found, 
    // or the get location timeout has triggered
    function getLocation() {
        PWR_GATE_EN.write(1);
        haveAccFix = false;
        if (loc == null) loc = Location(bootTime);

        return Promise(function(resolve, reject) {
            setLocTimeout(resolve, reject);

            loc.getLocation(LOCATION_ACCURACY, function(gpsFix) {
                haveAccFix = true;
                onAccFix(gpsFix, resolve, reject);
            }.bindenv(this));
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
            env.checkTempHumid(TEMP_THRESHOLD_LOW, TEMP_THRESHOLD_HIGH,
                HUMID_THRESHOLD_LOW, HUMID_THRESHOLD_HIGH, function(reading) {
                    if (reading != null) {
                        ::debug("--------------------------------------------------------------------------");
                        ::debug("[Main] Get temperature and humidity complete:")
                        ::debug(format("[Main] Current Humidity: %0.2f %s, Current Temperature: %0.2f °C", reading.humidity, "%", reading.temperature));
                        
                        if (reading.tempAlert != ALERT_DESC.IN_RANGE)  ::debug("[Main] Temp reading not in range.");
                        if (reading.humidAlert != ALERT_DESC.IN_RANGE) ::debug("[Main] Humid reading not in range.");
                        ::debug("--------------------------------------------------------------------------");

                        // Update alerts if needed, will start connecting if new alert condition is noted
                        checkForEnvAlerts(reading);
                    }

                    return resolve(reading);
                }.bindenv(this));
        }.bindenv(this))
    }

    // Returns a promise that resolves after getting an accelerometer reading
    function getAccelReading() {
        return Promise(function(resolve, reject) {
            move.getAccelReading(function(reading) {
                ::debug("--------------------------------------------------------------------------");
                ::debug("[Main] Get accelerometer reading complete:");
                if (reading != null) {
                    ::debug(format("[Main] Acceleration (G): x = %0.4f, y = %0.4f, z = %0.4f", reading.x, reading.y, reading.z));
                } 
                ::debug("--------------------------------------------------------------------------");
                return resolve(move.getMagnitude(reading));
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
            battery.checkStatus(BATTERY_THRESH_LOW, function(status) {
                ::debug("--------------------------------------------------------------------------");
                ::debug("[Main] Get battery status complete:")
                ::debug("[Main] Remaining cell capacity: " + status.capacity + "mAh");
                ::debug("[Main] Percent of battery remaining: " + status.percent + "%");
                ::debug("--------------------------------------------------------------------------");

                // Update alerts if needed, will start connecting if new alert condition is noted
                checkForBattAlerts(status);
                return resolve(status);
            }.bindenv(this));
        }.bindenv(this))
    }

    // Actions 
    // -------------------------------------------------------------

    // Helper that iterates over all alerts, deleting all that have been resolved 
    // and setting all other's reported flags to true, then stores the updated alerts
    function clearAlerts() {
        local updated = AlertManager.clearReported(persist.getAlerts());
        persist.storeAlerts(updated);
    }

    // Helper that takes raw env reading values, and checks if any of those readings 
    // are in/out of range (based on alert conditions), then updates the stored 
    // alerts as needed, creating new alerts or resolving existing alerts 
    function checkForEnvAlerts(envReadings) {
        local alerts = persist.getAlerts();

        // Make sure to check/update all alert types base on new readings
        // TEMP_LOW, TEMP_HIGH, HUMID_LOW, HUMID_HIGH
        local envAlertsUpdated  = AlertManager.checkEnvAlert(alerts, envReadings);

        if (envAlertsUpdated) {
            // Stored alerts have been updated, re-store 
            persist.storeAlerts(alerts);

            // We have an alert to report, so start connecting if we aren't already
            // NOTE: Calling connect if we are already connecting is ok, since  
            // ConnectionManager library manages this condition
            // Try to connect
            cm.connect();

            // Return true to trigger report send
            return true;
        }

        return false;
    }

    // Helper that takes raw battery reading values, and checks if any of those readings 
    // are in/out of range (based on alert conditions), then updates the stored 
    // alerts as needed, creating new alerts or resolving existing alerts 
    function checkForBattAlerts(batteryStatus) {
        local alerts = persist.getAlerts();

        // Make sure to check/update all alert types base on new readings
        // BATTERY_LOW
        local battAlertsUpdated = AlertManager.checkBattAlert(alerts, batteryStatus);

        if (battAlertsUpdated) {
            // Stored alerts have been updated, re-store 
            persist.storeAlerts(alerts);

            // We have an alert to report, so start connecting if we aren't already
            // NOTE: Calling connect if we are already connecting is ok, since  
            // ConnectionManager library manages this condition
            // Try to connect
            cm.connect();

            // Return true to trigger report send
            return true;
        }

        return false;
    }

    // Helper that checks the readings stored in the accelerometer's FIFO buffer 
    // to determine if an impact event has occured. If so, and alert is created 
    // and stored
    function checkImpact() {
        local alerts            = persist.getAlerts();
        local impactAlert       = move.checkImpact(IMPACT_THRESHOLD);
        local impactAlrtUpdated = AlertManager.checkImpactAlert(alerts, impactAlert);
        
        // If we have not detected movemnt or impact alert then power down
        if (!impactAlrtUpdated) return;

        // Update stored alerts with shock event
        persist.storeAlerts(alerts);

        // We have an alert to report, so start connecting if we aren't already
        // NOTE: Calling connect if we are already connecting is ok, since  
        // ConnectionManager library manages this condition
        // Try to connect
        cm.connect();

        return impactAlert;
    }

    // Helper that uses the current location and the stored (last reported) location 
    // to determine if the distance the device has moved. If this disance is greater 
    // than the distance threshold, then the distance is returned otherwise null 
    // is returned 
    function checkDistance(fix) {
        ::debug("[Main] Calculating distance...");

        // Woke on movement, check distance before reporting
        if ("rawLat" in fix && "rawLon" in fix) {
            local lastReportedLoc = persist.getLocation();

            // No stored location - can't determine distance, so send report 
            if (lastReportedLoc == null) {
                ::debug("[Main] No stored location. Scheduling report to update location...");
                return null;
            } 

            ::debug("[Main] Verified lat and lon in location data. Filtering GPS data...");
            local locHasChanged = loc.filterGPS(fix.rawLat, fix.rawLon, lastReportedLoc.lat, lastReportedLoc.lon, GPS_FILTER);
            if (locHasChanged) {
                ::debug("[Main] Location greater than filter. Calculating distance...");
                ::debug("[Main] Current location: lat " + fix.rawLat + ", lon " + fix.rawLon);
                ::debug("[Main] Last reported location: lat " + lastReportedLoc.lat + ", lon " + lastReportedLoc.lon);

                // Param order: new lat, new lon, old lat old lon
                local dist = loc.calculateDistance(fix.rawLat, fix.rawLon, lastReportedLoc.lat, lastReportedLoc.lon);
            
                // Report if we have moved more than the minimum distance since our last report
                if (dist >= DISTANCE_THRESHOLD_M) {
                    ::debug("[Main] Distance above threshold. Scheduling report...");
                    return dist;
                }
            }
            ::debug("[Main] Location did not change significantly.");
        } else {
            // Woke on movement, can't check distance
            ::debug("[Main] GPS data did not have lat & lon, so can't calculate distance");
        }

        return null;
    }

    // Takes raw data and returns a report table
    function createReport(alerts, envReadings, battStatus, accelReading = null, gpsFix = null, distance = null) {
        local report = {
            "secSinceBoot" : (hardware.millis() - bootTime) / 1000.0,
            "ts"           : time(),
            "movement"     : persist.getMoveDetected()
        }

        if (battStatus != null)   report.battStatus <- battStatus;
        if (accelReading != null) report.magnitude  <- accelReading;
        if (distance != null)     report.distance   <- distance;
        if (alerts != null)       report.alerts     <- alerts;

        if (envReadings != null) {
            report.temperature <- envReadings.temperature;
            report.humidity    <- envReadings.humidity;
        }

        if (gpsFix != null) {
            report.fix <- gpsFix;
        } else {
            local mostAccFix = loc.gpsFix;
            // If GPS got a fix of any sort
            if (mostAccFix != null) {
                // Log the fix summery
                ::debug(format("[Main] fixType: %s, numSats: %s, accuracy: %s", mostAccFix.fixType.tostring(), mostAccFix.numSats.tostring(), mostAccFix.accuracy.tostring()));
                // Add to report if fix was within the reporting accuracy
                if (mostAccFix.accuracy <= LOCATION_REPORT_ACCURACY) report.fix <- mostAccFix;
            }
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
            // NOTE: Calling connect if we are already connecting is ok, since  
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
        ::debug("[Main] Accel is enabled: " + move._isAccelEnabled() + ", accel int enabled: " + move._isAccelIntEnabled() + ", movement flag: " + persist.getMoveDetected());

        // Send to agent
        ::debug("[Main] Sending device status report to agent");
        msgr.send(MSG_REPORT, report);
    }

    // Sleep Management
    // -------------------------------------------------------------

    // Calculates and updates the stored report time
    function updateReportingTime() {
        local now = time();

	    // If report timer expired set based on current time offset with by the boot ts
        local reportTime = now + REPORT_TIME_SEC - (bootTime / 1000);

        // Update report time if it has changed
        persist.setReportTime(reportTime);

        ::debug("[Main] Next report time " + reportTime + ", in " + (reportTime - now) + "s");
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
            wakeTime = (adjForTimeAwake) ? (now + CHECK_IN_TIME - (bootTime / 1000)) : (now + CHECK_IN_TIME);
            persist.setWakeTime(wakeTime);
        }

        local sleepTime = (wakeTime - now);
        ::debug("[Main] Setting sleep timer: " + sleepTime + "s");
        return sleepTime;
    }

    // Helper that makes delays if Offline Assist message refresh request is not in 
    // process, re-enables movement detection then puts the device to sleep
    function powerDown(enableMovementWake = true) {
        // Cancel max wake timer if it is still running
        cancelMaxWakeTimeout();

        if (gettingOfflineAssist) {
            // Postpone for the ammount of time a message should ack in, 
            // then check again
            imp.wakeup(MSG_ACK_TIMEOUT, powerDown.bindenv(this))
        }

        // (Re)set movement interrupt settings (catch-all in case we updated interrupt to detect
        // impact while we were awake)
        if (enableMovementWake) {
            move.enMotionDetect(MOVEMENT_THRESHOLD, ACCEL_IMPACT_INT_DURATION, onMovePinStateChange.bindenv(this));
        }

        sleep();
    }

    // Helper that puts the device to sleep for the ammount of time determined by
    // getSleepTimer helper
    function sleep() {
        // Log how long we have been awake
        local now = hardware.millis();
        ::debug("[Main] Time since code started: " + (now - bootTime) + "ms");
        ::debug("[Main] Going to sleep...");

        lpm.sleepFor(getSleepTimer());
    }

    // Timer Helpers
    // -------------------------------------------------------------

    // Creates a timer that powers down GPS power after set time, parameters
    // are the resolve and reject functions generated by a promise.
    function setLocTimeout(resolve, reject) {
        // Ensure only one timer is set
        cancelLocTimeout();
        // Start a timer to send report if no GPS fix is found
        gpsFixTimer = imp.wakeup(LOCATION_TIMEOUT_SEC, function() {
            ::debug("[Main] GPS failed to get an accurate fix. Disabling GPS power.");
            PWR_GATE_EN.write(0);

            // Pass null to indicate we did not get an accurate fix
            return resolve(null);
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

    // Returns boolean, if offline assist messages should be refreshed 
    // based on the current time
    function shouldGetOfflineAssist() {
        local lastChecked = persist.getOfflineAssestChecked();
        return (lastChecked == null || time() >= (lastChecked + OFFLINE_ASSIST_REQ_MAX));
    }

	// Sets the stored wake and report time values to the current time
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

    // Returns a boolean if the GPS is powered up
    function areGettingLocation() {
        return (PWR_GATE_EN.read() == 1);
    }

}

// Runtime
// -----------------------------------------------------------------------

// Start controller
MainController();
