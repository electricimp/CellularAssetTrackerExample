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

// Hardware Abstraction Layer
// NOTE: All hardware objects are mapped to GLOBAL 
// variables. These variables are used throughout 
// the code, so vairable names should NOT be changed.

// imp006-breakout rev2.0   

// LED Pins
LED_RED           <- hardware.pinR;
LED_GREEN         <- hardware.pinXA;
LED_BLUE          <- hardware.pinXB;

// Power Gate for MikroBus/Grove
PWR_GATE_EN       <- hardware.pinXU;

BATT_CHGR_OTG     <- hardware.pinYC;
BATT_CHGR_INT     <- hardware.pinXM;

PRIMARY_BATT_V_EN <- hardware.pinYG;
PRIMARY_BATT_V    <- hardware.pinXD;

// Sensor & MikroBus i2c 
SENSOR_I2C      <- hardware.i2cLM;     
ACCEL_INT       <- hardware.pinW;      
TEMP_HUMID_ADDR <- 0xBE;
ACCEL_ADDR      <- 0x32;
BATT_CHGR_ADDR  <- 0xD6;
FUEL_GAUGE_ADDR <- 0x6C;   

CLICK_SPI       <- hardware.spiEFGH;
CLICK_UART      <- hardware.uartXEFGH;
CLICK_RESET     <- hardware.pinYH;
CLICK_INT       <- hardware.pinW;   // NOTE: This is the same as accel int 
CLICK_PWM       <- hardware.pinXG;

GROVE_I2C       <- hardware.i2cTU;
GROVE_AD1       <- hardware.pinN;
GROVE_AD2       <- hardware.pinXN;

// Recommended for offline logging, remove when in production    
LOGGING_UART    <- hardware.uartXEFGH;
