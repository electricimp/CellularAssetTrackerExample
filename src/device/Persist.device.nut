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
    WAKE_TIME              = "wake", 
    REPORT_TIME            = "report",
    MOVE_DETECTED          = "move",
    LOCATION               = "loc",
    OFFLINE_ASSIST_CHECKED = "offAssistChecked"
}

// Manages Persistant Storage  
// Dependencies: SPIFlashFileSystem Libraries
// Initializes: SPIFlashFileSystem Libraries
class Persist {

    _sffs                = null;

    reportTime           = null;
    wakeTime             = null;
    moveDetected         = null;
    location             = null;
    offlineAssistChecked = null;

    constructor() {
        // TODO: Update with more optimized circular buffer.
        // TODO: Optimize erases to happen when it won't keep device awake
        _sffs = SPIFlashFileSystem(0x000000, 0x200000);
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

    function getMoveDetected() {
        // If we have a local copy, return the local copy
        if (moveDetected != null) return moveDetected;
        
        if (_sffs.fileExists(PERSIST_FILE_NAMES.MOVE_DETECTED)) {
            local file = _sffs.open(PERSIST_FILE_NAMES.MOVE_DETECTED, "r");
            local move = file.read();
            file.close();
            move.seek(0, 'b');
            moveDetected = (move.readn('b') == 1);
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

        // Try to get report time from SPI, store a local copy
        if (_sffs.fileExists(PERSIST_FILE_NAMES.LOCATION)) {
            local file = _sffs.open(PERSIST_FILE_NAMES.LOCATION, "r");
            local rt = file.read();
            file.close();
            rt.seek(0, 'b');
            location = {};
            location.lat <- rt.readn('i');
            location.lng <- rt.readn('i');
        }
        
        // Return location or null if it is not found
        return location;;
    }

        // Use a date string to get assist messages for that day
    function getAssistByDate(fileName) {
        if (!_sffs.fileExists(fileName)) return null;

        // Open, get all assist messages for that file name (date)
        local file = _sffs.open(fileName, "r");
        local msgs = file.read();
        file.close();

        return msgs;
    }

    function getOfflineAssestChecked() {
        // If we have a local copy, return the local copy
        if (offlineAssistChecked != null) return offlineAssistChecked;

         // Try to get report time from SPI, store a local copy
        if (_sffs.fileExists(PERSIST_FILE_NAMES.OFFLINE_ASSIST_CHECKED)) {
            local file = _sffs.open(PERSIST_FILE_NAMES.OFFLINE_ASSIST_CHECKED, "r");
            local rt = file.read();
            file.close();
            rt.seek(0, 'b');
            offlineAssistChecked = rt.readn('i');
        }
        
        // Return offlineAssistChecked or null if it is not found
        return offlineAssistChecked;;
    }

    function setMoveDetected(detected) {
        // Only update if movement flag has changed
        if (moveDetected == detected) return;

        // Erase outdated movement data
        if (_sffs.fileExists(PERSIST_FILE_NAMES.MOVE_DETECTED)) {
            _sffs.eraseFile(PERSIST_FILE_NAMES.MOVE_DETECTED)
        }

        // Update local and stored wake time with the new time
        moveDetected = detected;
        local file = _sffs.open(PERSIST_FILE_NAMES.MOVE_DETECTED, "w");
        file.write(_serializeMove(moveDetected));
        file.close();
        ::debug("[Persist] Movement flag stored: " + moveDetected);
    }

    function setWakeTime(newTime) {
        // Only update if timestamp has changed
        if (wakeTime == newTime) return;

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
    }

    function setReportTime(newTime) {
        // Only update if timestamp has changed
        if (reportTime == newTime) return;

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
    }

    function setLocation(lat, lng) {
        // Only update if location has changed
        if (location != null && location.len() == 2 && lat == location.lat && lng == location.lng) return;

        // Erase outdated report time
        if (_sffs.fileExists(PERSIST_FILE_NAMES.LOCATION)) {
            _sffs.eraseFile(PERSIST_FILE_NAMES.LOCATION)
        }

        // Update local and stored report time with the new time
        location = {
            "lat" : lat,
            "lng" : lng
        };
       
        local file = _sffs.open(PERSIST_FILE_NAMES.LOCATION, "w");
        file.write(_serializeLocation(lat, lng));
        file.close();
        ::debug("[Persist] Location stored lat: " + lat + ", lng: " + lng);
    }

    function setOfflineAssistChecked(newTime) {
        if (offlineAssistChecked == newTime) return;

        // Erase outdated report time
        if (_sffs.fileExists(PERSIST_FILE_NAMES.OFFLINE_ASSIST_CHECKED)) {
            _sffs.eraseFile(PERSIST_FILE_NAMES.OFFLINE_ASSIST_CHECKED)
        }

        // Update local and stored report time with the new time
        offlineAssistChecked = newTime;
        
        local file = _sffs.open(PERSIST_FILE_NAMES.OFFLINE_ASSIST_CHECKED, "w");
        file.write(_serializeTimestamp(offlineAssistChecked));
        file.close();
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
            // TODO: erase all stale messages as well as today's
            // If day exists, delete it as new data will be fresher
            if (_sffs.fileExists(day)) {
                _sffs.eraseFile(day);
            }

            // Write day msgs
            local file = _sffs.open(day, "w");
            file.write(msgs);
            file.close();
        }
    }

    function _serializeTimestamp(ts) {
        local b = blob(4);
        b.writen(ts, 'i');
        b.seek(0, 'b');
        return b;
    }

    function _serializeLocation(lat, lng) {
        local b = blob(8);
        b.writen(lat, 'i');
        b.writen(lng, 'i');
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
                if (name != PERSIST_FILE_NAMES.WAKE_TIME &&
                    name != PERSIST_FILE_NAMES.REPORT_TIME && 
                    name != PERSIST_FILE_NAMES.LOCATION &&
                    name != PERSIST_FILE_NAMES.OFFLINE_ASSIST_CHECKED &&
                    _isStale(name)) {
                        ::debug("[Persist] Erasing SFFS file name: " + name);
                        // Erase old assist message
                        _sffs.eraseFile(name);
                } 
            }
        } catch (e) {
            ::error("[Persist] Error erasing old assist messages: " + e);
        }
    }

    function _isStale(name) {
        // Unexpected file name erase it
        if (name.len() != 8) return true; 

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
            return true;
        }
    }
    
}
