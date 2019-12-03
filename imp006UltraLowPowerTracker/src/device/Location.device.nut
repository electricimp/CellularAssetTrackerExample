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
            "onLocation" : function(loc) {
                if ("error" in loc) ::error("[Location] Error getting fix: " + loc.error);
                
                if ("fix" in loc) {
                    local disabled = BG96_GPS.disableGNSS();
                    ::debug("[Location] GPS disabled: " + disabled);

                    local fix = {};
                    if (typeof loc.fix == "table") {
                        fix = _parseLatLon(loc.fix);
                        fix.secToFix <- (hardware.millis() - bootTime) / 1000.0;
                    } else {
                        local err = "Error unable to parse location data: " + loc.fix;
                        ::error("[Location] " + err);
                        fix.error <- err;
                    }
                    onAccurateFix(fix);
                }
            }.bindenv(this)
        }
        BG96_GPS.enableGNSS(opts);
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

    function _parseLatLon(fix) {
        // Update latitude if needed
        if ("lat" in fix) {
            local lat = fix.lat;
            local lastCharIdx = lat.len() - 1;
            local lastChar = lat.slice(lastCharIdx);
            // If the last char in the string is "N", "S"
            if (lastChar == "N" || lastChar == "S") {
                fix.lat = GPSParser.parseLatitude(lat.slice(0, lastCharIdx), lastChar);
            }
        }
        // Update longitude if needed
        if ("lon" in fix) {
            local lon = fix.lon;
            local lastCharIdx = lon.len() - 1;
            local lastChar = lon.slice(lon.len() - 1);
            // If the last char in the string is "E", "W"
            if (lastChar == "E" || lastChar == "W") {
                fix.lon = GPSParser.parseLongitude(lon.slice(0, lastCharIdx), lastChar);
            }
        }

        return fix;
    }

}
