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
    INVALID_PARAM               = 501,
    OPERATION_NOT_SUPPORTED     = 502,
    GNSS_SUBSYSTEM_BUSY         = 503,
    SESSION_IS_ONGOING          = 504,
    SESSION_NOT_ACTIVE          = 505,
    OPERATION_TIMEOUT           = 506,
    FUNCTION_NOT_ENABLED        = 507,
    TIME_INFO_ERROR             = 508,
    XTRA_NOT_ENABLED            = 509,
    VALIDITY_TIME_OUT_OF_RANGE  = 512,
    INTERNAL_RESOURCE_ERROR     = 513,
    GNSS_LOCKED                 = 514,
    END_BY_E911                 = 515,
    NOT_FIXED_NOW               = 516,
    GEO_FENCE_ID_DOES_NOT_EXIST = 517,
    UNKNOWN_ERROR               = 549
}

enum AT_COMMAND {
    // "AT+CFUN=4" ?? fro, zandr code?

    // Stand Alone Mode (only mode supported)
    TURN_ON_GNSS             = "AT+QGPS=1",
    // Params: (mode), sec to get fix, acc in meters, num of fixes to collect, check every x sec        
    TURN_ON_GNSS_WITH_PARMAS = "AT+QGPS=1,%i,%i,%i,%i",
    TURN_OFF_GNSS            = "AT+QGPSEND",

    CONFIG_GNSS_PARAMS      = "AT+QGPSCFG",

    GET_GPS_LOC             = "AT+QGPSLOC?",

    WRITE_GPS_XTRA_FILE     = "AT+QGPSXTRADATA",
    WRITE_GPS_XTRA_TIME     = "AT+QGPSXTRATIME",
    ENABLE_GPS_ONE_XTRA     = "AT+QGPSXTRA=1",
    DISABLE_GPS_ONE_XTRA    = "AT+QGPSXTRA=0",
    IS_GPS_ONE_XTRA_VALID   = "AT+QGPSXTRADATA?"
}

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
        // Turn on GPS
        // Query for location data??
        // Turn off GPS
    }

    function assistIsValid() {
        // Enable one xtra & restart module??
        // Check if current messages are valie
    }

    function writeAssistMsgs(msgs, onDone = null) {
        // Enable one xtra & restart module??

        // AT+QFUPL="UFS:xtra2.bin",60831,60                Select the gps file
        // AT+QGPSXTRATIME=0,“2017/11/08,15:30:30”,1,1,5    inject the time
        // AT+QGPSXTRADATA=“UFS:xtra2.bin”                  inject the file
        // AT+QFDEL=“UFS:xtra2.bin”                         delete the file from UFS
        // AT+QGPS=1                                        turn on GNSS
    }

    function _writeATCommand(cmd) {
        local response = imp.setquirk(0x75636feb, command);
        return response;
    }

}
