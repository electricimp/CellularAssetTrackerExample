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
        // TODO: Format and send data to cloud service
    }

    function _formatData(data) {
        local formatted = {
            "deviceID"   : _devId,
            "agentID"    : _agentId,
            "ts"         : ("ts" in data) ? data.ts : time()
        }

        if ("temperature" in data) formatted.temperature <- data.temperature;
        if ("humidity" in data)    formatted.humidity    <- data.humidity;
        if ("battStatus" in data)  formatted.battery     <- data.battStatus.percent;
        if ("magnitude" in data)   formatted.magnitude   <- data.magnitude;
        if ("fix" in data) {
            if ("lat" in data.fix) formatted.lat  <- data.fix.lat;
            if ("lon" in data.fix) formatted.long <- data.fix.lon;
        }

        return formatted;
    }

}
