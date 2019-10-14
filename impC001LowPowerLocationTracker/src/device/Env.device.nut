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

// Environmental Monitoring File

// Manages Environmental Monitoring  
// Dependencies: HTS221 (may configure sensor i2c)
// Initializes: HTS221
class Env {

    th = null;

    constructor(configureI2C = null) {
        if (configureI2C) SENSOR_I2C.configure(CLOCK_SPEED_400_KHZ);
        th = HTS221(SENSOR_I2C, TEMP_HUMID_ADDR);
    }

    // Takes a reading and passes result to callback 
    function getTempHumid(cb) {
        th.setMode(HTS221_MODE.ONE_SHOT);
        // Trigger callback only if we get a reading.
        th.read(function(res) {
            if ("error" in res) {
                ::error("[Env] Temperature/Humidity reading error: " + res.error);
                cb(null);
            } else {
                cb(res);
            }
        }.bindenv(this))
    }

    // Takes a reading and checks that it is in range
    // Passes a table with readings, boolean if in readings range, and time to callback
    function checkTempHumid(tMin, tMax, hMin, hMax, cb) {
        getTempHumid(function(res) {
            if ("error" in res || !("temperature" in res) || !("humidity" in res)) {
                ::error("[Env] Temperature/Humidity reading error: " + res.error);
                cb(null);
            } else {
                local alert = res;
                alert.tempAlert  <- _checkReading(res.temperature, tMin, tMax);
                alert.humidAlert <- _checkReading(res.humidity, hMin, hMax);
                alert.ts         <- time();
                cb(alert);
            }
        }.bindenv(this))
    }

    function _checkReading(reading, min, max) {
        // ::debug("[Env] Checking reading: " + reading + " min " + min + " max " + max);
        if (reading < min) return ALERT_DESC.LOW;
        if (reading > max) return ALERT_DESC.HIGH;
        return ALERT_DESC.IN_RANGE;
    }
    
}
