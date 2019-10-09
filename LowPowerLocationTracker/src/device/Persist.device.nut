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

// NOTE: Assist Offline Messages are store with date string file names
// formatted as YYYYMMDD. These messages are purged when stale using a 
// check based on file name length. If a file name has a length of 8 please
// update _isAssistOfflineDateFile method.
enum PERSIST_FILE_NAMES {
    WAKE_TIME              = "wake", 
    REPORT_TIME            = "report",
    OFFLINE_ASSIST_CHECKED = "offAssistChecked",
    MOVE_DETECTED          = "move",
    LOCATION               = "loc",
    ALERTS                 = "alerts"
}

const ALERT_BLOB_SIZE = 14;

// Manages Persistant Storage  
// Dependencies: SPIFlashFileSystem Libraries
// Initializes: SPIFlashFileSystem Libraries
class Persist {

    _sffs                = null;

    reportTime           = null;
    wakeTime             = null;
    offlineAssistChecked = null;
    moveDetected         = null;
    location             = null;
    alerts               = null;

    constructor() {
        // TODO: Update with more optimized circular buffer.
        // TODO: Optimize erases to happen when it won't keep device awake

        // NOTE: Currently set to use the entire flash. If SPI flash is needed
        // for any other part of the application adjust the start and end here
        _sffs = SPIFlashFileSystem();
        _sffs.init(_onInit.bindenv(this));
    }

    // For debug purposes
    function _onInit(files) {
        // Log how many files we found
        ::debug(format("[Persist] Found %d files", files.len()));

        // Log all the information returned about each file:
        foreach(file in files) {
            ::debug(format("[Persist]  %d: %s (%d bytes)", file.id, file.fname, file.size));
        }
    }

    function getWakeTime() {
        // If we have a local copy, return the local copy
        if (wakeTime != null) return wakeTime;

        // Try to get wake time from SPI, store a local copy
        local wt = _readFile(PERSIST_FILE_NAMES.WAKE_TIME);
        if (wt != null) {
            wakeTime = wt.readn('i');
        }

        // Return wake time or null if it is not found
        return wakeTime;
    }

    function getReportTime() {
        // If we have a local copy, return the local copy
        if (reportTime != null) return reportTime;

        // Try to get report time from SPI, store a local copy
        local rt = _readFile(PERSIST_FILE_NAMES.REPORT_TIME);
        if (rt != null) reportTime = rt.readn('i');
        
        // Return report time or null if it is not found
        return reportTime;;
    }

    function getMoveDetected() {
        // If we have a local copy, return the local copy
        if (moveDetected != null) return moveDetected;

        local moved = _readFile(PERSIST_FILE_NAMES.MOVE_DETECTED);
        if (moved != null) {
            moveDetected = (moved.readn('b') == 1);
        } else {
            // Movement is only stored when an event has happened. If no file 
            // has been stored, then no movement event has happened.
            moveDetected = false;            
        }

        return moveDetected;
    }

    function getLocation() {
        // If we have a local copy, return the local copy
        if (location != null) return location;

        // Try to get last location from SPI, store a local copy
        local rawLoc = _readFile(PERSIST_FILE_NAMES.LOCATION);
        if (rawLoc != null) {
            location = {};
            location.lat <- rawLoc.readn('i');
            location.lon <- rawLoc.readn('i');
        }

        // Return location or null if it is not found
        return location;
    }

    // Use a date string to get assist messages for that day
    function getAssistByDate(fileName) {
        // Return blob of msgs or null for all assist messages 
        // for the specified file name (date)
        return _readFile(fileName);
    }

    function getOfflineAssestChecked() {
        // If we have a local copy, return the local copy
        if (offlineAssistChecked != null) return offlineAssistChecked;

        // Try to get offline assist checked time from SPI, store a local copy
        local tm = _readFile(PERSIST_FILE_NAMES.OFFLINE_ASSIST_CHECKED);
        if (tm != null) offlineAssistChecked = tm.readn('i');

        // Return offlineAssistChecked or null if it is not found
        return offlineAssistChecked;
    }

    function getAlerts() {
        if (alerts != null) return alerts;

        local rawAlerts = _readFile(PERSIST_FILE_NAMES.ALERTS);
        if (rawAlerts != null) {
            alerts = _deserializeAlerts(rawAlerts);
        } else {
            alerts = [];
        }

        return alerts
    }

    function setMoveDetected(detected) {
        // Only update if movement flag has changed
        if (moveDetected == detected) return;

        // Update local and stored movement flag
        moveDetected = detected;
        _writeFile(PERSIST_FILE_NAMES.MOVE_DETECTED, _serializeMove(moveDetected));
        
        ::debug("[Persist] Movement flag stored: " + moveDetected);
    }

    function setWakeTime(newTime) {
        // Only update if timestamp has changed
        if (wakeTime == newTime) return;

        // Update local and stored wake time with the new time
        wakeTime = newTime;
        _writeFile(PERSIST_FILE_NAMES.WAKE_TIME, _serializeTimestamp(wakeTime));

        ::debug("[Persist] Wake time stored: " + wakeTime);
    }

    function setReportTime(newTime) {
        // Only update if timestamp has changed
        if (reportTime == newTime) return;

        // Update local and stored report time with the new time
        reportTime = newTime;
        _writeFile(PERSIST_FILE_NAMES.REPORT_TIME, _serializeTimestamp(reportTime));

        ::debug("[Persist] Report time stored: " + reportTime);
    }

    function setLocation(lat, lon) {
        // Only update if location has changed
        if (location != null && location.len() == 2 && lat == location.lat && lon == location.lon) return;

        // Update local and stored location
        location = {
            "lat" : lat,
            "lon" : lon
        };
        _writeFile(PERSIST_FILE_NAMES.LOCATION, _serializeLocation(lat, lon));
       
        ::debug("[Persist] Location stored lat: " + lat + ", lon: " + lon);
    }

    function setOfflineAssistChecked(newTime) {
        if (offlineAssistChecked == newTime) return;

        // Update local and stored offline assist checked time with the new time
        offlineAssistChecked = newTime;
        _writeFile(PERSIST_FILE_NAMES.OFFLINE_ASSIST_CHECKED, _serializeTimestamp(offlineAssistChecked));

        ::debug("[Persist] Offline assist refesh time stored: " + offlineAssistChecked);
    }

    // Takes a table of assist messages, where table slots are date strings
    // NOTE: these date strings will be used as file names
    function storeAssist(msgsByDate) {
        // TODO: May want to optimize erases to happen when it won't keep device awake
        // Erase old messages
        _eraseStaleAssistMsgs();

        // Store new messages
        foreach(day, msgs in msgsByDate) {
            // If day exists, delete it as new data will be fresher
            _writeFile(day, msgs);
        }
    }

    // Note: this will wipe out all stored alerts and replace with the alerts 
    // passed in. Use helper sameAsStoredAlerts to see if alerts match, before 
    // storing. 
    function storeAlerts(newAlerts) {
        if (newAlerts == null || newAlerts.len() == 0) {
            alerts = null;
            if (_sffs.fileExists(PERSIST_FILE_NAMES.ALERTS)) _sffs.eraseFile(PERSIST_FILE_NAMES.ALERTS);

            ::debug("[Persist] No alerts stored");
        } else {
            // Update local copy
            alerts = newAlerts;
            
            ::debug("[Persist] Storing " + newAlerts.len() + " alerts.");
            ::debug("--------------------------------------------------------");
            foreach(alert in alerts) {
                foreach(k, v in alert) {
                    ::debug("[Persist] Alert table, k: " + k + " v: " + v);
                }
            }
            ::debug("--------------------------------------------------------");

            // Update stored copy
            _writeFile(PERSIST_FILE_NAMES.ALERTS, _serializeAlerts(alerts));
            ::debug("[Persist] New alerts stored. Number of alerts: " + alerts.len());
        }
    }

    function sameAsStoredAlerts(newAlerts) {
        local stored = _serializeAlerts(alerts);
        local new = _serializeAlerts(newAlerts);
        return crypto.equals(stored, new);
    }

    function _readFile(fname) {
        local rawFile = null;
        if (_sffs.fileExists(fname)) {
            local file = _sffs.open(fname, "r");
            rawFile = file.read();
            file.close();
            rawFile.seek(0, 'b');
        }
        return rawFile;
    }

    function _writeFile(fname, data) {
        // Erase outdated data
        if (_sffs.fileExists(fname)) {
            _sffs.eraseFile(fname);
        }

        local file = _sffs.open(fname, "w");
        file.write(data);
        file.close();
    }

    function _serializeTimestamp(ts) {
        local b = blob(4);
        b.writen(ts, 'i');
        b.seek(0, 'b');
        return b;
    }

    function _serializeLocation(lat, lon) {
        local b = blob(8);
        b.writen(lat, 'i');
        b.writen(lon, 'i');
        b.seek(0, 'b');
        return b;
    }

    function _serializeMove(detected) {
        local b = blob(1);
        local int = (detected) ? 1 : 0;
        b.writen(int, 'b');
        b.seek(0, 'b');
        return b;
    }

    function _eraseStaleAssistMsgs() {
        try {
            local files = _sffs.getFileList();
            foreach(file in files) {
                local name = file.fname;
                // Find assist files for dates that have already passed
                if (_isAssistOfflineDateFile(name) && _isStale(name)) {
                        ::debug("[Persist] Erasing SFFS file name: " + name);
                        // Erase old assist message
                        _sffs.eraseFile(name);
                } 
            }
        } catch (e) {
            ::error("[Persist] Error erasing old assist messages: " + e);
        }
    }

    function _isAssistOfflineDateFile(name) {
        // TODO: Update this if file names change!!!
        // NOTE: 
            // File names: wake(4), report(6), offAssistChecked(16), move(4),
            // loc(3), alerts(8)
            // Offline assist file name are Date strings formatted YYYYMMDD, so 
            // have a length of 8 
        return (name.len() == 8);
    }

    function _isStale(name) {
        // Unexpected file name length don't erase it
        if (name.len() != 8) return false; 

        local today = date();
        local year  = today.year;   
        local month = today.month + 1;  // date() month returns integer 0-11
        local day   = today.day;  

        ::debug("[Persist] Checking if file " + name + " is stale");

        try {
            // File name/Date string YYYYMMDD
            local fyear  = name.slice(0, 4).tointeger();
            local fmonth = name.slice(4, 6).tointeger();
            local fday   = name.slice(6).tointeger();

            // Check year
            if (fyear > year) return false;
            if (fyear < year) return true;

            // Year is the same, Check month
            if (fmonth > month) return false;
            if (fmonth < month) return true;

            // Year and month are the same, Check day
            return (fday < day);
        } catch(e) {
            ::error("[Persist] Error converitng file name to integer: " + name);
            // Don't erase file
            return false;
        }
    }

    function _serializeAlerts(alrts) {
        local numAlerts = alrts.len();
        if (numAlerts == 0) return;

        local b = blob(numAlerts * ALERT_BLOB_SIZE);
        foreach(alert in alrts) {
            b.writeblob(_serializeAlert(alert));
        }

        b.seek(0, 'b');
        return b;
    }

    function _deserializeAlerts(rawAlerts) {
        rawAlerts.seek(0, 'b');
        local alrts = [];

        for (local i = 0; i < rawAlerts.len(); i += ALERT_BLOB_SIZE) {
            local alert = {};
            alert.type     <- rawAlerts.readn('b');
            alert.trigger  <- rawAlerts.readn('f');
            alert.created  <- rawAlerts.readn('i');
            alert.resolved <- rawAlerts.readn('i');
            alert.reported <- (rawAlerts.readn('b') == 1);  
            alrts.push(alert);
        }
        
        return alrts;
    }

    function _serializeAlert(alert) {
        local b = blob(ALERT_BLOB_SIZE);
        local reported = (alert.reported) ? 1 : 0;

        b.writen(alert.type, 'b');      // 8 bit int (0-5)
        b.writen(alert.trigger, 'f');   // 32 bit float (reading value)
        b.writen(alert.created, 'i');   // 32 bin int (timestamp)
        b.writen(alert.resolved, 'i');  // 32 bin int (timestamp)
        b.writen(reported, 'b');        // 8 bit int (0-1)
        b.seek(0, 'b');

        return b;
    }

}
