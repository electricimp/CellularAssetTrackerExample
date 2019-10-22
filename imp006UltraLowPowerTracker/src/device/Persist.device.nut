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

// Persistant Storage File

enum PERSIST_FILE_NAMES {
    WAKE_TIME     = "wake", 
    REPORT_TIME   = "report",
    ALERTS        = "alerts"
}

// Manages Persistant Storage  
// Dependencies: SPIFlashFileSystem Libraries
// Initializes: SPIFlashFileSystem Libraries
class Persist {

    _sffs      = null;

    reportTime = null;
    wakeTime   = null;
    alerts     = null;

    constructor() {
        // TODO: Update with more optimized circular buffer.
        // TODO: Optimize erases to happen when it won't keep device awake
        // Note: This currently is configured to use all the SPI Flash, update
        // if another part of the application (ie ReplayMessanger) are added.
        _sffs = SPIFlashFileSystem();
        _sffs.init();
    }

    function getWakeTime() {
        // If we have a local copy, return the local copy
        if (wakeTime != null) return wakeTime;

        // Try to get wake time from SPI, store a local copy
        if (_sffs.fileExists(PERSIST_FILE_NAMES.WAKE_TIME)) {
            local file = _sffs.open(PERSIST_FILE_NAMES.WAKE_TIME, "r");
            local wt = file.read();
            file.close();
            wt.seek(0, 'b');
            wakeTime = wt.readn('i');
        }

        // Return wake time or null if it is not found
        return wakeTime;
    }

    function setWakeTime(newTime) {
        // Only update if timestamp has changed
        if (wakeTime == newTime) return false;

        // Erase outdated wake time
        if (_sffs.fileExists(PERSIST_FILE_NAMES.WAKE_TIME)) {
            _sffs.eraseFile(PERSIST_FILE_NAMES.WAKE_TIME)
        }

        // Update local and stored wake time with the new time
        wakeTime = newTime;
        local file = _sffs.open(PERSIST_FILE_NAMES.WAKE_TIME, "w");
        file.write(_serializeTimestamp(wakeTime));
        file.close();

        ::debug("[Persist] Wake time stored: " + wakeTime);
        return true;
    }

    function getReportTime() {
        // If we have a local copy, return the local copy
        if (reportTime != null) return reportTime;

        // Try to get report time from SPI, store a local copy
        if (_sffs.fileExists(PERSIST_FILE_NAMES.REPORT_TIME)) {
            local file = _sffs.open(PERSIST_FILE_NAMES.REPORT_TIME, "r");
            local rt = file.read();
            file.close();
            rt.seek(0, 'b');
            reportTime = rt.readn('i');
        }
        
        // Return report time or null if it is not found
        return reportTime;;
    }

    function setReportTime(newTime) {
        // Only update if timestamp has changed
        if (reportTime == newTime) return false;

        // Erase outdated report time
        if (_sffs.fileExists(PERSIST_FILE_NAMES.REPORT_TIME)) {
            _sffs.eraseFile(PERSIST_FILE_NAMES.REPORT_TIME)
        }

        // Update local and stored report time with the new time
        reportTime = newTime;
        local file = _sffs.open(PERSIST_FILE_NAMES.REPORT_TIME, "w");
        file.write(_serializeTimestamp(reportTime));
        file.close();

        ::debug("[Persist] Report time stored: " + reportTime);
        return true;
    }

    function getAlerts() {
        if (alerts != null) return alerts;

        // Try to get alerts from SPI, store a local copy
        if (_sffs.fileExists(PERSIST_FILE_NAMES.ALERTS)) {
            local file = _sffs.open(PERSIST_FILE_NAMES.ALERTS, "r");
            local alrts = file.read();
            file.close();
            alrts.seek(0, 'b');
            alerts = alrts.readn('b');
        }
        
        // If no alerts are stored, then set local copy to none (no need to store this)
        if (alerts == null) alerts = ALERT_TYPE.NONE;

        // Return alerts
        return alerts;
    }

    function setAlerts(newAlerts) {
        // Only upate if alerts have changed
        if (alerts == newAlerts) return false;

        // Erase outdated alerts
        if (_sffs.fileExists(PERSIST_FILE_NAMES.ALERTS)) {
            _sffs.eraseFile(PERSIST_FILE_NAMES.ALERTS)
        }

        // Update local and stored alerts with the new alerts
        alerts = newAlerts;
        local file = _sffs.open(PERSIST_FILE_NAMES.ALERTS, "w");
        file.write(_serializeByte(alerts));
        file.close();

        ::debug(format("[Persist] Alerts stored: 0x%02X", alerts));
        return true;
    }

    function getAlert(type) {
        // Make sure we have alerts stored locally
        getAlerts();
        // Return the integer (enum) value of the specified alert 
        return (type & alerts);
    }

    function setAlert(type, detected) {
        // Make sure we have alerts stored locally
        getAlerts();
        // Toggle alert if needed
        local newAlerts = (detected) ? (type | alerts) : (~type & alerts);
        // Set alerts if needed
        return setAlerts(newAlerts);
    }

    function _serializeTimestamp(ts) {
        local b = blob(4);
        b.writen(ts, 'i');
        b.seek(0, 'b');
        return b;
    }

    function _serializeByte(byte) {
        local b = blob(1);
        b.writen(byte, 'b');
        b.seek(0, 'b');
        return b;
    }

}
