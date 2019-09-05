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

 // Cloud Service File 

const STUBBED_PRESSURE_VAL = 1018.65;
const STUBBED_GATEWAY_ID   = "test_gateway";
const STUBBED_TYPE         = "test_type_cellular";

const CLOUD_DATA_ENDPOINT  = "@{CLOUD_DATA_ENDPOINT}"; 

// Manages Cloud Service Communications  
// Dependencies: YOUR CLOUD SERVICE LIBRARY 
// Initializes: YOUR CLOUD SERVICE LIBRARY
class Cloud {

    _service = null;
    
    _devId   = null; 
    _agentId = null;

    constructor() {
        _devId   = imp.configparams.deviceid; 
        _agentId = split(http.agenturl(), "/").top();
    }

    function send(data) {
        local body    = http.jsonencode(_formatData(data));
        local headers = {
            "Content-Type" : "application/json"
        } 
        local req = http.post(CLOUD_DATA_ENDPOINT, headers, body);

        ::debug("[Cloud] Sending data to cloud:");
        ::debug("[Cloud] " + body);
        // Send formatted data to your cloud service
        req.sendasync(_onSent.bindenv(this));
    }

    function _formatData(data) {
        local formatted = {
            "deviceID"   : _devId,
            "agentID"    : _agentId,
            "pressure"   : STUBBED_PRESSURE_VAL, 
            "gateway_id" : STUBBED_GATEWAY_ID,
            "type"       : STUBBED_TYPE, 
            "ts"         : ("ts" in data) ? data.ts : time()
        }

        if ("temperature" in data) formatted.temperature <- data.temperature;
        if ("humidity" in data)    formatted.humidity    <- data.humidity;
        if ("battStatus" in data)  formatted.battery     <- data.battStatus.capacity;
        if ("fix" in data) {
            if ("lat" in data.fix) formatted.lat  <- data.fix.lat;
            if ("lon" in data.fix) formatted.long <- data.fix.lon;
        }

        // Only add accel data if movement was detected
        if (data.movement && "accel" in data) formatted.shockAlert <- data.accel;

        return formatted;
    }

    function _onSent(resp) {
        ::debug("[Cloud] Data request sent. Status Code: " + resp.statuscode);
    }

}