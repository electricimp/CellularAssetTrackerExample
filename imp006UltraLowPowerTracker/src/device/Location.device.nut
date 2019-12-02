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

// NOTE: This is an alpha version of a private library. Not published yet.
@include "github:electricimp-cse/BG96_GPS/BG96_GPS.device.nut@develop"

const LOC_POLLING_TIME_SEC = 1;

// Manages Location Application Logic
// Dependencies: imp006 GPS
// Initializes: None
class Location {
    
    bootTime = null;

    constructor(_bootTime) {
        bootTime = _bootTime;
    }

    function getLocation(accuracy, onAccurateFix) {
        ::debug("[Location] Location request started. Enabling GNSS...");
        local opts = {
            "accuracy"   : accuracy,
            "locMode"    : BG96_GNSS_LOCATION_MODE.ONE, 
            "onLocation" : function(fix) {
                if ("error" in fix) ::error("[Location] Error getting fix: " + fix.error);
                
                if ("data" in fix) {
                    BG_96_GPS.disableGNSS();
                    // TODO: parse data
                    local fix = _parseLocData(fix.data);
                    fix.secToFix <- (hardware.millis() - bootTime) / 1000.0;
                    onAccurateFix(fix);
                }
            }.bindenv(this)
        }
        BG_96_GPS.enableGNSS(opts);
    }

    function assistIsValid() {
        // NOTE: Cannot write assist files with AT
        // command quirk, so just return true
        return true;
    }

    function writeAssistMsgs(msgs, onDone = null) {
        // Cannot do this with AT Command quirk!! Just trigger callback
        onDone("Write assist not supported yet");
    }

    function _parseLocData(data) {
        ::debug("[Location] Parsing location data: " + data);
        try {
            local parsed = split(data, ",");
            return {
                "time"       : _formatTimeStamp(parsed[11], parsed[0]),
                "utc"        : parsed[0],
                "lat"        : GPS.parseLatitude(parsed[1], parsed[2]),
                "lon"        : GPS.parseLongitude(parsed[3], parsed[4]),
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
            return { "error" : "Error parsing GPS data " + e };
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

    function _logResp(resp) {
        ::debug("[Location] Parsed AT response:");
        foreach(k, v in resp) {
            ::debug("[Location]   " + k + ": " + v);
        }
    }

}
