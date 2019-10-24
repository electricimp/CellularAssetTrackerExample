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

// Shared Agent/Device constants

// Messaging Names
const MSG_ASSIST = "assist";
const MSG_REPORT = "report";

// Alert Type Values
// NOTE: These values should correspond to ALERT_TYPE_REPORTED
enum ALERT_TYPE {
    NONE       = 0x00,
    MOVEMENT   = 0x01,
    BATT_LOW   = 0x02,
    TEMP_HIGH  = 0x04,
    HUMID_HIGH = 0x08
}

// Alert Type Reported
// NOTE: These values should correspond to ALERT_TYPE_REPORTED
enum ALERT_TYPE_REPORTED {
    NONE       = 0x00,    
    MOVEMENT   = 0x10,
    BATT_LOW   = 0x20,
    TEMP_HIGH  = 0x40,
    HUMID_HIGH = 0x80
}