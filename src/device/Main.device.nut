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
#require "UBloxM8N.device.lib.nut:1.0.1"
#require "UbxMsgParser.lib.nut:2.0.0"
#require "LIS3DH.device.lib.nut:2.0.2"
#require "HTS221.device.lib.nut:2.0.1"
#require "SPIFlashFileSystem.device.lib.nut:2.0.0"
#require "ConnectionManager.lib.nut:3.1.1"
#require "MessageManager.lib.nut:2.4.0"
#require "LPDeviceManager.device.lib.nut:0.1.0"
#require "UBloxAssistNow.device.lib.nut:0.1.0"
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
@include __PATH__ + "/Location.device.nut"
@include __PATH__ + "/Motion.device.nut"
@include __PATH__ + "/Battery.device.nut"
@include __PATH__ + "/Env.device.nut"

// Main Application
// -----------------------------------------------------------------------

// Wake every x seconds to check if report should be sent
const CHECK_IN_TIME_SEC      = 300;
// Wake every x seconds to send a report, regaurdless of check results
const REPORT_TIME_SEC        = 900;

// Force in Gs that will trigger movement interrupt
const MOVEMENT_THRESHOLD     = 0.05;
// Accuracy of GPS fix in meters (Location data will only be accurate to this value, 
// so GPS_FILTER and DISTANCE_THRESHOLD_M should be based on this value)
const LOCATION_ACCURACY      = 10;
// Maximum time to wait for GPS to get a fix, before trying to send report
// NOTE: This should be less than the MAX_WAKE_TIME
const LOCATION_TIMEOUT_SEC   = 60; 
const OFFLINE_ASSIST_REQ_MAX = 43200; // Limit requests to every 12h (12 * 60 * 60) 
// Distance threshold in meters (~100ft)
const DISTANCE_THRESHOLD_M   = 30;
// GPS can sometimes jump around when sitting still, use this filter to eliminate 
// small jumps while not moving. This will also limit the number of times we calculate
// distance.
const GPS_FILTER             = 0.00015;
// Constant used to validate imp's timestamp
const VALID_TS_YEAR          = 2019;

// Maximum time to stay awake
const MAX_WAKE_TIME          = 65;
// Low battery alert threshold in percentage
const BATTERY_LOW_THRESH     = 10;


class MainController {

    // Supporting CLasses
    cm                   = null;
    mm                   = null;
    lpm                  = null;
    move                 = null;
    loc                  = null;
    persist              = null;

    // Report Values
    fix                  = null;
    battStatus           = null;
    thReading            = null;

    // Application Variables
    bootTime             = null;
    sleep                = null;
    gpsFixTimer          = null;
    reportSent           = null; 
    checkDistance        = null;
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
        ::debug("--------------------------------------------------------------------------");       PWR_GATE_EN.configure(DIGITAL_OUT, 0);

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
        lpm.onConnect(onConnect.bindenv(this));
        cm.onTimeout(onConnTimeout.bindenv(this));

        // Initialize Message Manager for agent/device communication
        mm = MessageManager({"connectionManager" : cm});
        mm.onTimeout(mmOnTimeout.bindenv(this));

        // Set tracking flag defaults
        reportSent           = false;
        gettingOfflineAssist = false;
        checkDistance        = false;
    }

    // MM handlers
    // -------------------------------------------------------------

    // Global MM Timeout handler
    function mmOnTimeout(msg, wait, fail) {
        ::debug("[Main] MM message timed out");
        fail();
    }

    // MM onFail handler for report
    function mmOnReportFail(msg, err, retry) {
        ::error("[Main] Report send failed");
        powerDown();
    }

    // MM onFail handler for assist messages
    function mmOnAssistFail(msg, err, retry) {
        ::error("[Main] Request for assist messages failed, retrying");
        retry();
    }

    // MM onAck handler for report
    function mmOnReportAck(msg) {
        // Report successfully sent
        ::debug("[Main] Report ACK received from agent");

        // Clear & reset movement detection
        if (persist.getMoveDetected()) {
            // Re-enable movement detection
            move.enable(MOVEMENT_THRESHOLD, onMovement.bindenv(this));
            // Toggle stored movement flag
            persist.setMoveDetected(false);
        }

        // NOTE: Reporting is scheduled based purely on interval, if movement caused 
        // report the next report will be scheduled based on when that report was sent
        updateReportingTime();
        powerDown();
    }

    // MM onReply handler for assist messages
    function mmOnAssist(msg, response) {
        if (response == null) {
            ::debug("[Main] Didn't receive any Assist messages from agent.");
            return;
        }

        // Response contains assist messages from cloud
        local assistMsgs = response;

        if (msg.payload.data == ASSIST_TYPE.OFFLINE) {
            ::debug("[Main] Offline assist messages received from agent");

            // Store all offline assist messages by date
            persist.storeAssist(response);
            // Update time we last checked
            persist.setOfflineAssistChecked(time());
            // Offline assist messages stored, toggle flag
            gettingOfflineAssist = false;

            // Get today's date string/file name
            local todayFileName = Location.getAssistDateFileName();
            // Select today's offline assist messages only
            if (todayFileName in response) {
                assistMsgs = response.todayFileName;
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

    // Connection & Connection Flow Handlers
    // -------------------------------------------------------------

    // Connection Flow
    function onConnect() {
        ::debug("[Main] Device connected...");

        // Configure UBLOX Assist message handlers
        local mmHandlers = {
            "onReply" : mmOnAssist.bindenv(this),
            "onFail"  : mmOnAssistFail.bindenv(this)
        };

        if (shouldGetOfflineAssist()) {
            gettingOfflineAssist = true;
            // Refresh offline assist messages
            ::debug("[Main] Requesting offline assist messages from agent/Assist Now.");
            mm.send(MM_ASSIST, ASSIST_TYPE.OFFLINE, mmHandlers);
        }

        // Note: We are only checking for GPS fix, The assumption is that an accurate GPS fix will
        // take longer than getting battery status, env readings etc.
        if (fix != null) {
            sendReport();
        } else {
            // We don't have a fix, request assist online data
            ::debug("[Main] Requesting online assist messages from agent/Assist Now.");
            mm.send(MM_ASSIST, ASSIST_TYPE.ONLINE, mmHandlers);
        }
    }

    // Connection time-out flow
    function onConnTimeout() {
        ::debug("[Main] Connection try timed out.");
        powerDown();
    }

    // Wake up on timer flow
    function onScheduledWake() {
        ::debug("[Main] Wake reason: " + lpm.wakeReasonDesc());

        // Configure Interrupt Wake Pin
        // No need to (re)enable movement detection, these settings
        // are stored in the accelerometer registers. Just need
        // to configure the wake pin.
        move.configIntWake(onMovement.bindenv(this));

        // Set a limit on how long we are connected
        // Note: Setting a fixed duration to sleep here means next connection
        // will happen in calculated time + the time it takes to complete all
        // tasks.
        lpm.doAsyncAndSleep(function(done) {
            // Set sleep function
            sleep = done;
            // Check if we need to connect and report
            checkAndSleep();
        }.bindenv(this), getSleepTimer(), MAX_WAKE_TIME);
    }

    // Wake up on interrupt flow
    function onMovementWake() {
        ::debug("[Main] Wake reason: " + lpm.wakeReasonDesc());

        // Set a limit on how long we are connected
        // Note: Setting a fixed duration to sleep here means next connection
        // will happen in calculated time + the time it takes to complete all
        // tasks.
        lpm.doAsyncAndSleep(function(done) {
            // Set sleep function
            sleep = done;
            // Check if we need to connect and report
            onMovement();
        }.bindenv(this), getSleepTimer(), MAX_WAKE_TIME);
    }

    // Wake up flow - triggered on all connects except interrupt or timer
    function onBoot(wakereson) {
        ::debug("[Main] Wake reason: " + lpm.wakeReasonDesc());

        // Enable movement monitor
        move.enable(MOVEMENT_THRESHOLD, onMovement.bindenv(this));
	    // NOTE: overwriteStoredConnectSettings method only needed if CHECK_IN_TIME_SEC
        // and/or REPORT_TIME_SEC have been changed - leave this while in development
        overwriteStoredConnectSettings();

        // Send report if connected or alert condition noted, then sleep
        // Set a limit on how long we are connected
        // Note: Setting a fixed duration to sleep here means next connection
        // will happen in calculated time + the time it takes to complete all
        // tasks.
        lpm.doAsyncAndSleep(function(done) {
            // Set sleep function
            sleep = done;
            // Check if we need to connect and report
            checkAndSleep();
        }.bindenv(this), getSleepTimer(), MAX_WAKE_TIME);
    }

    // Actions
    // -------------------------------------------------------------

    // Create and send device status report to agent
    function sendReport() {
        reportSent = true;

        local report = {
            "secSinceBoot" : (hardware.millis() - bootTime) / 1000.0,
            "ts"           : time(),
            "movement"     : persist.getMoveDetected()
        }

        if (battStatus != null) report.battStatus <- battStatus;
        if (thReading != null) {
            report.temperature <- thReading.temperature;
            report.humidity    <- thReading.humidity;
        }
        if (fix != null) {
            report.fix <- fix;
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

        // MOVEMENT DEBUGGING LOG
        ::debug("[Main] Accel is enabled: " + move._isAccelEnabled() + ", accel int enabled: " + move._isAccelIntEnabled() + ", movement flag: " + persist.getMoveDetected());

        // Send to agent
        ::debug("[Main] Sending device status report to agent");
        local mmHandlers = {
            "onAck" : mmOnReportAck.bindenv(this),
            "onFail" : mmOnReportFail.bindenv(this)
        };
        mm.send(MM_REPORT, report, mmHandlers);
    }

    // Powers up GPS and starts location message filtering for accurate fix
    function getLocation() {
        PWR_GATE_EN.write(1);
        if (loc == null) loc = Location(bootTime);
        loc.getLocation(LOCATION_ACCURACY, onAccFix.bindenv(this));
    }

    // Initializes Battery monitor and gets battery status
    function getBattStatus() {
        // NOTE: I2C is configured when Motion class is initailized in the
        // constructor of this class, so we don't need to configure it here.
        // Initialize Battery Monitor without configuring i2c
        local battery = Battery(false);
        battery.getStatus(onBatteryStatus.bindenv(this));
    }

    // Initializes Env Monitor and gets temperature and humidity
    function getSensorReadings() {
        // Get temperature and humidity reading
        // NOTE: I2C is configured when Motion class is initailized in the 
        // constructor of this class, so we don't need to configure it here.
        // Initialize Environmental Monitor without configuring i2c
        local env = Env();
        env.getTempHumid(onTempHumid.bindenv(this));
    }

    // Updates report time
    function updateReportingTime() {
        local now = time();

	    // If report timer expired set based on current time offset with by the boot ts
        local reportTime = now + REPORT_TIME_SEC - (bootTime / 1000);

        // Update report time if it has changed
        persist.setReportTime(reportTime);

        ::debug("[Main] Next report time " + reportTime + ", in " + (reportTime - now) + "s");
    }

    function setLocTimeout() {
        // Ensure only one timer is set
        cancelLocTimeout();
        // Start a timer to send report if no GPS fix is found
        gpsFixTimer = imp.wakeup(LOCATION_TIMEOUT_SEC, onGpsFixTimerExpired.bindenv(this));
    }

    function cancelLocTimeout() {
        if (gpsFixTimer != null) {
            imp.cancelwakeup(gpsFixTimer);
            gpsFixTimer = null;
        }
    }

    // Async Action Handlers
    // -------------------------------------------------------------

    // Pin state change callback & on wake pin action
    // If event valid, disables movement interrupt and store movement flag
    function onMovement() {
        // Check if new movement occurred
        // Note: Motion detected method will clear interrupt when called
        if (move.detected()) {
            ::debug("[Main] Movement event detected");

            // Check distance 
            checkDistance = true;
            // Set timer to send report if GPS doesn't get a fix, and we are connected
            setLocTimeout();
            getLocation();

            // TODO: track if location check fails 
        } else {
            // Sleep til next check-in time
            // Note: To conserve battery power, after movement interrupt
            // we are not connecting right away, we will report movement
            // on the next scheduled check-in time
            powerDown();
        }
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

    // If report timer expires before accurate GPS fix is not found,
    // disable GPS power and send report if connected
    function onGpsFixTimerExpired() {
        ::debug("[Main] GPS failed to get an accurate fix. Disabling GPS power.");
        PWR_GATE_EN.write(0);

         // Send report if connection handler has already run
        // and report has not been sent
        if (lpm.isConnected()) sendReport();
    }

    // Stores fix data, and powers down the GPS
    function onAccFix(gpxFix) {
        // We got a fix, cancel timer to send report automatically
        cancelLocTimeout();

        ::debug("[Main] Got fix");
        fix = gpxFix;

        ::debug("[Main] Disabling GPS power");
        PWR_GATE_EN.write(0);

        if (checkDistance) {
            ::debug("[Main] Movement triggered location. Check distance...");
            // Woke on movement, check distance before reporting
            if ("rawLat" in fix && "rawLon" in fix) {
                local lastReportedLoc = persist.getLocation();

                // no stored - can't determine distance send report
                if (lastReportedLoc == null) {
                    ::debug("[Main] No stored location. Scheduling report to update location...");
                    reportMovement()
                    return;
                } 

                ::debug("[Main] Got location in report. Filtering GPS data...");
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
                        reportMovement();
                        return;
                    }
                }
            } else {
                // Woke on movement, can't check distance
                ::debug("[Main] GPS data did not have lat & lon, so can't calculate distance");
            }

            // Sleep til next check-in time
            // Note: To conserve battery power, after movement interrupt
            // we are not connecting right away, we will report movement
            // on the next scheduled check-in time
            powerDown();
        } else {
            // Update last reported lat & lon for calculating distance
            if ("rawLat" in fix && "rawLon" in fix) persist.setLocation(fix.rawLat, fix.rawLon);

            // Send report if connection handler has already run
            // and report has not been sent
            if (lpm.isConnected() && !reportSent) sendReport();
        }

    }

    // Stores battery status for use in report
    function onBatteryStatus(status) {
        ::debug("[Main] Get battery status complete:")
        ::debug("[Main] Remaining cell capacity: " + status.capacity + "mAh");
        ::debug("[Main] Percent of battery remaining: " + status.percent + "%");
        battStatus = status;
    }

    // Stores temperature and humidity reading for use in report
    function onTempHumid(reading) {
        ::debug("[Main] Get temperature and humidity complete:")
        ::debug(format("C[Main] urrent Humidity: %0.2f %s, Current Temperature: %0.2f °C", reading.humidity, "%", reading.temperature));
        thReading = reading;
    }

    // Sleep Management
    // -------------------------------------------------------------

    // Updates check-in time if needed, and returns time in sec to sleep for
    function getSleepTimer() {
        local now = time();
        // Get stored wake time
        local wakeTime = persist.getWakeTime();

        // Our timer has expired, update it to next interval
        if (wakeTime == null || now >= wakeTime) {
            wakeTime = now + CHECK_IN_TIME_SEC - (bootTime / 1000);
            persist.setWakeTime(wakeTime);
        }

        local sleepTime = (wakeTime - now);
        ::debug("[Main] Setting sleep timer: " + sleepTime + "s");
        return sleepTime;
    }

    function reportMovement() {
        // Store movement flag
        persist.setMoveDetected(true);
        // Connect/Run connection flow
        // Connection handler will trigger report send
        lpm.connect();
        // Get sensor readings for report
        getSensorReadings();
        // Get battery status
        getBattStatus();
    }

    // Runs a check and triggers sleep flow
    function checkAndSleep() {
        if (shouldConnect() || lpm.isConnected()) {
            if (!lpm.isConnected()) ::debug("[Main] Connecting...");
            // Set timer to send report if GPS doesn't get a fix, and we are connected
            setLocTimeout();
            // Connect/Run connection flow
            lpm.connect();
            // Power up GPS and try to get a location fix
            getLocation();
            // Get sensor readings for report
            getSensorReadings();
            // Get battery status
            getBattStatus();
        } else {
            // Go to sleep
            powerDown();
        }
    }

    // Debug logs about how long divice was awake, and puts device to sleep
    function powerDown() {
        // Log how long we have been awake
        local now = hardware.millis();
        ::debug("[Main] Time since code started: " + (now - bootTime) + "ms");
        ::debug("[Main] Going to sleep...");

        local sleepTime;
        if (sleep == null) {
            sleepTime = getSleepTimer();
            ::debug("[Main] Setting sleep timer: " + sleepTime + "s");
        }

        // Put device to sleep 
        (sleep != null) ? sleep() : lpm.sleepFor(sleepTime);
    }

    // Helpers
    // -------------------------------------------------------------

    function shouldGetOfflineAssist() {
        local lastChecked = persist.getOfflineAssestChecked();
        return (lastChecked == null || time() >= (lastChecked + OFFLINE_ASSIST_REQ_MAX));
    }

	// Overwrites currently stored wake and report times
    function overwriteStoredConnectSettings() {
        local now = time();
        persist.setWakeTime(now);
        persist.setReportTime(now);
    }

    // Returns boolean, checks for event(s) or if report time has passed
    function shouldConnect() {
        // Check for events
        // Note: We are not currently storing position changes. The assumption
        // is that if we change position then movement will be detected and trigger
        // a report to be generated.
        local haveMoved = persist.getMoveDetected();
        ::debug("[Main] Movement detected: " + haveMoved);
        if (haveMoved) return true;

        // NOTE: We need a valid timestamp to determine sleep times.
        // If the imp looses all power, a connection to the server is
        // needed to get a valid timestamp.
        local validTS = validTimestamp();
        ::debug("[Main] Valid timestamp: " + validTS);
        if (!validTS) return true;

        // Check if report time has passed
        local now = time();
        local shouldReport = (now >= persist.getReportTime());
        ::debug("[Main] Time to send report: " + shouldReport);
        return shouldReport;
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
