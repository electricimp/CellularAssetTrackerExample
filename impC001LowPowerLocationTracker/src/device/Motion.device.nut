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

// Motion Monitoring File

// Number of readings per sec
const ACCEL_DATA_RATE           = 100;
// Number of readings condition must be true before int triggered 
const ACCEL_MOVE_INT_DURATION   = 50;  
// Number of readings condition must be true before int triggered 
const ACCEL_IMPACT_INT_DURATION = 5;

// Manages Motion Sensing  
// Dependencies: LIS3DH (may configure sensor i2c)
// Initializes: LIS3DH
class Motion {

    accel = null;

    constructor(configureI2C) {
        if (configureI2C) SENSOR_I2C.configure(CLOCK_SPEED_400_KHZ);
        accel = LIS3DH(SENSOR_I2C, ACCEL_ADDR);
    }

    function enable(threshold, enImpact = false, onInterrupt = null) {
        ::debug("[Motion] Enabling motion detection");

        // Configures and enables motion interrupt
        enableAccel();
        if (enImpact) {
            enableImpact();
            ::debug("[Motion] Enabling impact detection");
        }
        enMotionDetect(threshold, ACCEL_MOVE_INT_DURATION, onInterrupt);
    }

    function enableAccel() {
        accel.reset();
        accel.setDataRate(ACCEL_DATA_RATE);
        accel.setMode(LIS3DH_MODE_LOW_POWER);
        accel.enable(true);
    }

    function enMotionDetect(threshold, dur, onInterrupt = null) {
        configIntWake(onInterrupt);
        accel.configureHighPassFilter(LIS3DH_HPF_AOI_INT1, LIS3DH_HPF_CUTOFF1, LIS3DH_HPF_NORMAL_MODE);
        accel.getInterruptTable();
        accel.configureInertialInterrupt(true, threshold, dur);
        accel.configureInterruptLatching(false);
    }

    function enableImpact() {
        // Clear buffer if overrun has occurred
        accel.configureFifo(true, LIS3DH_FIFO_BYPASS_MODE);
        // Re-enable buffer
        accel.configureFifo(true, LIS3DH_FIFO_STREAM_TO_FIFO_MODE);
    }

    function configIntWake(onInterrupt = null) {
        // Configure interrupt pin 
            // Wake when interrupt occurs 
            // (optional) With state change callback to catch interrupts when awake
        if (onInterrupt != null) {
            ACCEL_INT.configure(DIGITAL_IN_WAKEUP, onInterrupt);
        } else {
            ACCEL_INT.configure(DIGITAL_IN_WAKEUP);
        }
    }

    // This method does NOT clear the latched interrupt pin. 
    // It disables the accelerometer, high pass filter, interrupt, FIFO buffer 
    // and reconfigures wake pin.  
    function disable() {
        ::debug("[Motion] Disabling motion detection");

        // Disables accelerometer 
        accel.setDataRate(0);
        accel.enable(false);

        // Set FIFO buffer to bypass mode
        accel.configureFifo(false);

        // Disable accel interrupt and high pass filter
        accel.configureHighPassFilter(LIS3DH_HPF_DISABLED);
        accel.configureInertialInterrupt(false);

        // Note: Configuring pin doesn't chage pin's current state
        // Reconfiguring int pin 
            // Disables wake on pin high
            // Clear state change callback
        ACCEL_INT.configure(DIGITAL_IN_PULLDOWN); 
    }

    // Returns boolean if interrupt was detected. 
    // Note: Calling this method clears the interrupt.
    function detected() {
        ::debug("[Motion] Checking and clearing interrupt");
        // Get interrupt table. Note this clears the interrupt data 
        local res = accel.getInterruptTable();
        // Return boolean - if motion event has occurred
        return res.int1;
    }

    function getAccelReading(cb) {
        if (_isAccelEnabled()) {
            local r = accel.getAccel();
            if ("error" in r) {
                ::error("[Motion] Error reading accel " + r.error);
                cb(null);
            } else {
                cb(r);
            }
        } else {
            // Enable accel
            accel.setDataRate(ACCEL_DATA_RATE);
            accel.enable(true);
            // Give time for at least one reading to happen
            local odr = 1.0 / ACCEL_DATA_RATE;
            imp.wakeup(odr, function() {
                local r = accel.getAccel();
                // Disable accel
                accel.setDataRate(0);
                accel.enable(false);
                if ("error" in r) {
                    ::error("[Motion] Error reading accel " + r.error);
                    cb(null);
                } else {
                    cb(r);
                }
            }.bindenv(this));
        }
    }

    function checkImpact(thresh) {
        if (!_isAccelImpactEnabled()) return;

        // Get data from FIFO buffer, determine the maximum magnitude
        local stats = accel.getFifoStats();
        local max = null;
        local raw = null;
        for (local i = 0 ; i < stats.unread ; i++) {
            local data = accel.getAccel();
            local mag = getMagnitude(data);
            if (mag != null && mag > max) {
                max = mag;
                raw = data;
            }
        }

        // Reset FIFO Buffer
        enableImpact();

        local alert = {
            "impactDetected" : (max != null && max > thresh),
            "raw"            : raw, 
            "magnitude"      : max, 
            "ts"             : time()
        }

        if (alert.impactDetected) {
            ::debug(format("[Motion] Max mag: %f, Accel (x,y,z): [%f, %f, %f]", max, raw.x, raw.y, raw.z));
        }

        return alert;
    }

    function getMagnitude(data) {
        if (data == null) return null;

        if ("x" in data && "y" in data && "z" in data) {
            local x = data.x;
            local y = data.y;
            local z = data.z;
            return math.sqrt(x*x + y*y + z*z);
        }
        
        return null;
    }

    // Helper returns bool if accel is enabled
    function _isAccelEnabled() {
        // bits 0-2 xyz enabled, 3 low-power enabled, 4-7 data rate
        local val = accel._getReg(LIS3DH_CTRL_REG1);
        return (val & 0x07) ? true : false;
    }

    // Helper returns bool if accel inertial interrupt is enabled
    function _isAccelIntEnabled() {
        // bit 7 inertial interrupt is enabled,
        local val = accel._getReg(LIS3DH_CTRL_REG3);
        return (val & 0x40) ? true : false;
    }

    function _isAccelImpactEnabled() {
        local val = accel._getReg(LIS3DH_FIFO_CTRL_REG);
        return (val & 0xC0) ? true : false;
    }

}
