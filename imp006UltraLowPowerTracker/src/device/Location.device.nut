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

// Location/GPS File

// const DEFAULT_GPS_ACCURACY = 9999;
// const GPS_UART_BAUDRATE    = 115200;
// const LOCATION_CHECK_SEC   = 1;

// enum FIX_TYPE {
//     NO_FIX,
//     DEAD_REC_ONLY,
//     FIX_2D,
//     FIX_3D,
//     GNSS_DEAD_REC,
//     TIME_ONLY
// }

enum AT_ERROR_CODE {
    FILE_INVALID_INPUT              = "400",
    FILE_SIZE_MISMATCH              = "401",
    FILE_READ_ZERO_BYTE             = "402",
    FILE_DRIVE_FULL                 = "403",
    FILE_NOT_FOUND                  = "405",
    FILE_INVALID_NAME               = "406",
    FILE_ALREADY_EXISTS             = "407",
    FILE_WRITE_FAIL                 = "409",
    FILE_OPEN_FAIL                  = "410",
    FILE_READ_FAIL                  = "411",
    FILE_MAX_OPEN_FILES             = "413",
    FILE_READ_ONLY                  = "414",
    FILE_INVALID_DESCRIPTOR         = "416",
    FILE_LIST_FAIL                  = "417",
    FILE_DELETE_FAIL                = "418",
    FILE_GET_DISK_INFO_FAIL         = "419",
    FILE_NO_SPACE                   = "420",
    FILE_TIMEOUT                    = "421",
    FILE_TOO_LARGE                  = "423",
    FILE_INVALID_PARAM              = "425",
    FILE_ALREADY_OPEN               = "426",
    GPS_INVALID_PARAM               = "501",
    GPS_OPERATION_NOT_SUPPORTED     = "502",
    GPS_GNSS_SUBSYSTEM_BUSY         = "503",
    GPS_SESSION_IS_ONGOING          = "504",
    GPS_SESSION_NOT_ACTIVE          = "505",
    GPS_OPERATION_TIMEOUT           = "506",
    GPS_FUNCTION_NOT_ENABLED        = "507",
    GPS_TIME_INFO_ERROR             = "508",
    GPS_XTRA_NOT_ENABLED            = "509",
    GPS_VALIDITY_TIME_OUT_OF_RANGE  = "512",
    GPS_INTERNAL_RESOURCE_ERROR     = "513",
    GPS_GNSS_LOCKED                 = "514",
    GPS_END_BY_E911                 = "515",
    GPS_NO_FIX_NOW                  = "516",
    GPS_GEO_FENCE_ID_DOES_NOT_EXIST = "517",
    GPS_UNKNOWN_ERROR               = "549"
}

enum AT_COMMAND {
    GET_GNSS_STATE           = "AT+QGPS?",    
    // Params:  mode - Stand Alone is the only mode supported(1), 
    //          sec max pos time (30), 
    //          fix accuracy in meters (50), 
    //          num of checks after fix before powering down GPS (0 - continuous), 
    //          check every x sec (1)
    TURN_ON_GNSS             = "AT+QGPS=1,30,%i,0,%i",
    TURN_OFF_GNSS            = "AT+QGPSEND",
    // <latitude>,<longitude> format: ddmm.mmmm N/S,dddmm.mmmm E/W
    GET_GPS_LOC_MODE_0       = "AT+QGPSLOC=0",
    // <latitude>,<longitude> format: ddmm.mmmmmm N/S,dddmm.mmmmmm E/W
    GET_GPS_LOC_MODE_1       = "AT+QGPSLOC=1",
    // <latitude>,<longitude> format: (-)dd.ddddd,(-)ddd.ddddd
    GET_GPS_LOC_MODE_2       = "AT+QGPSLOC=2",

    ENABLE_GPS_ONE_XTRA      = "AT+QGPSXTRA=1",
    DISABLE_GPS_ONE_XTRA     = "AT+QGPSXTRA=0",
    IS_GPS_ONE_XTRA_VALID    = "AT+QGPSXTRADATA?",
    // Params: file name, file size, timeout
    UPLOAD_ONE_XTRA_FILE     = "AT+QFUPL=\"%s\",%i,%i",
    // Params:  inject jpsOneXTRA time (1) only option
    //          Current UTC or GPS time
    //          Type: GPS = 0, UTC = 1 (1)
    //          Force GPS to accept injected time (0 - allow, 1 - force) (0)
    //          Uncertainty of time (3500ms)
    INJECT_GPS_XTRA_TIME     = "AT+QGPSXTRATIME=0,\"%s\",1",
    // Params: file name
    INJECT_GPS_XTRA_FILE     = "AT+QGPSXTRADATA=\"%s\"",
    DELETE_ONE_XTRA_FILE     = "AT+QFDEL=\"%s\""
}

const LOC_POLLING_TIME_SEC = 1;

// Manages Location Application Logic
// Dependencies: imp006 GPS
// Initializes: None
class Location {
    
    gpsFix     = null;
    // accTarget  = null;
    // onAccFix   = null;

    bootTime   = null;

    constructor(_bootTime) {
        bootTime = _bootTime;
    }

    function getLocation(accuracy, onAccurateFix) {
        enableGNSS(accuracy);
        _pollLoc(onAccurateFix);
    }

    function assistIsValid() {
        // NOTE: Cannot write assist files with AT
        // command quirk, so just return true
        return true;

        // Enable & query if file is valid
        // TODO: handle case where GPS ONE EXTRA is not enabled
        _writeATCommand(AT_COMMAND.ENABLE_GPS_ONE_XTRA);
        local resp = _writeAndParseAT(AT_COMMAND.IS_GPS_ONE_XTRA_VALID);
        return resp.success;
    }

    function writeAssistMsgs(msgs, onDone = null) {
        // Cannot do this with AT Command quirk!! Just trigger callback
        onDone();

        // Here is the list of commands from example code:
        // Enable one xtra
            // AT_COMMAND.ENABLE_GPS_ONE_XTRA 
            // resart the module if needed??
        // Check if we have a valid file
            // AT_COMMAND.IS_GPS_ONE_XTRA_VALID
            // File is valid turn on GNSS done
            // File is invalid continue with steps
        // Get file form agent (WEB SERVICE URL)
        // Create file name (used 2-3x in process) 
            // ie format("xtra%04d%02d%02d.bin", d.year, (d.month+1), d.day);
        // Upload file to file system
            // format(AT_COMMAND.UPLOAD_ONE_XTRA_FILE, filename, file.len(), 10)
            // Wait for response - "CONNECT" (module is now in mode to write file)
            // Send/write binary file
            // Wait for response - "OK"
        // Inject file to GPS
            // Create timestamp Format: YYYY/MM/DD,hh:mm:ss
                // format("%04d/%02d/%02d,%02d:%02d:%02d", d.year, (d.month+1), d.day, d.hour, d.min, d.sec);
            // format(AT_COMMAND.INJECT_GPS_XTRA_TIME, "2019/09/23,14:20:42")
            // format(AT_COMMAND.INJECT_GPS_XTRA_FILE, "xtra20190923.bin")
        // Clean up files
            // AT_COMMAND.IS_GPS_ONE_XTRA_VALID
            // format(AT_COMMAND.DELETE_ONE_XTRA_FILE, "xtra20190923.bin")
        // Enable GNSS
            // AT_COMMAND.TURN_ON_GNSS
    }

    function enableGNSS(fixAccuracy) {
        if (!_isGNSSEnabled()) {
            local resp = _writeAndParseAT(format(AT_COMMAND.TURN_ON_GNSS, fixAccuracy, LOC_POLLING_TIME_SEC));
            if ("error" in resp) {
                ::error("[Location] Error enabling GNSS: " + resp.error);
                return false;
            }
            return resp.success;
        }
        return true;
    }

    function disableGNSS() {
        if (_isGNSSEnabled()) {
            local resp = _writeAndParseAT(AT_COMMAND.TURN_OFF_GNSS);
            if ("error" in resp) {
                ::error("[Location] Error disabling GNSS: " + resp.error);
                return false;
            }
            return resp.success;
        }
        return true;
    }

    function _isGNSSEnabled() {
        local resp = _writeAndParseAT(AT_COMMAND.GET_GNSS_STATE);
        if ("error" in resp) {
            ::error("[Location] Received AT error code: " + resp.error);
            return false;
        }
        // Response 
            // data = 0, GNSS disabled
            // data = 1, GNSS enabled
        return (resp.data == "1");
    }

    function _pollLoc(onLoc) {
        local fix = _getLoc();
        if (fix) {
            // Pass error or location fix to main application
            onLoc(fix);
        } else {
            imp.wakeup(LOC_POLLING_TIME_SEC, function() {
                _pollLoc(onLoc);
            }.bindenv(this));
        }
    }

    function _getLoc() {
        local resp = _writeAndParseAT(AT_COMMAND.GET_GPS_LOC_MODE_1);
        if ("error" in resp) {
            // Look for expected errors
            local errorCode = resp.error;
            switch (errorCode) {
                case AT_ERROR_CODE.GPS_NO_FIX_NOW:
                    return null;
                case AT_ERROR_CODE.GPS_SESSION_NOT_ACTIVE:
                    ::error("[Location] GPS not enabled.");
                    return {"error" : "Location request timed out"};
                default: 
                    ::error("[Location] GPS location request failed with error: " + errorCode);
                    return { "error" : "AT error code: " + errorCode};
            }
        }

        local fix = _parseLocData(resp.data);
        fix.secToFix <- (hardware.millis() - bootTime) / 1000.0;
        return fix;
    }

    function _writeAndParseAT(cmd) {
        local resp = _writeATCommand(cmd);
        return _parseATResp(resp);
    }

    // Note: This blocks until the response is returned
    function _writeATCommand(cmd) {
        return imp.setquirk(0x75636feb, cmd);
    }

    // Takes AT response and looks for OK, error and response data 
    // returns table that may contain slots: raw, error, data, success
    function _parseATResp(resp) {
        local parsed = {"raw" : resp};

        try {
            // ::debug("[Location] AT response: " + resp);
            // ::debug("[Location] AT response len: " + resp.len());

            parsed.success <- (resp.find("OK") != null);
            
            local start = resp.find(":");
            (start != null) ? start+=2 : start = 0;
            
            local newLine = resp.find("\n");
            local end = (newLine != null) ? newLine : resp.len();
        
            local data = resp.slice(start, end);
            
            if (resp.find("Error") != null) {
                parsed.error <- data;
            } else {
                parsed.data  <- data;
            }
        } catch(e) {
            parsed.error <- "Error parsing AT response: " + e;
        }

        return parsed;
    }

    function _parseLocData(data, formatLL = true) {
        // ::debug("[Location] Parsing location data: " + data);
        try {
            local parsed = split(data, ",");
            return {
                "time"       : _formatTimeStamp(parsed[11], parsed[0]),
                "utc"        : parsed[0],
                "lat"        : (formatLL) ? _formatLatLon(parsed[1], parsed[2]) : parsed[1] + parsed[2],
                "lon"        : (formatLL) ? _formatLatLon(parsed[3], parsed[4]) : parsed[3] + parsed[4],
                "hdop"       : parsed[5],
                "alt"        : parsed[6],
                "fixType"    : parsed[7],
                "cog"        : parsed[8],
                "spkm"       : parsed[9],
                "spkn"       : parsed[10],
                "date"       : parsed[11],
                "numSats"    : parsed[12]
            }
        } catch(e) {
            return {
                "error" : "Error parsing GPS data " + e
            }
        }
    }

    // Format GPS timestamp
    function _formatTimeStamp(d, utc) {
        // Input d: DDMMYY, utc HHMMSS.S
        // Formated result: YYYY-MM-DD HH:MM:SS.SZ
        return format("20%s-%s-%s %s:%s:%sZ", d.slice(4), 
                                              d.slice(2, 4), 
                                              d.slice(0, 2), 
                                              utc.slice(0, 2), 
                                              utc.slice(2, 4), 
                                              utc.slice(4));
    }

    // Format to decimal degrees
    function _formatLatLon(degMin, dir) {
        local idx = degMin.find(".");
        return ((dir == "S" || dir == "W") ? "-" : "") +
                 degMin.slice(0, (idx - 2)) + "." +
                 degMin.slice((idx - 2), idx) +
                 degMin.slice(idx + 1);
    }

    function _logResp(resp) {
        ::debug("[Location] Parsed AT response:");
        foreach(k, v in resp) {
            ::debug("[Location]   " + k + ": " + v);
        }
    }

}
