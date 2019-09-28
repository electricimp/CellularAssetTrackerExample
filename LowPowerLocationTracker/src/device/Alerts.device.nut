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

// Device Alert Processing File


// ALERT FORMATTING
// -----------------------------------------------------------------------
// Alerts are an array of alert tables
// Alert table description: 
// alert <- {
//     type     : enum ALERT_TYPE
//     trigger  : reading val that triggered alert
//     created  : timestamp when alert triggered first
//     resolved : timestamp when alert condition no longer active (or 0)
//     reported : boolean (if change has been reported - ie new alert, or newly resolved);
// }

// A global table with functions to help manage alerts, stores no state
// all alerts should be passed in and persisted in the main application.
// Dependencies: none
// Initializes: nothing
AlertManager <- {

    "checkForUnreported" : function(stored) {
        if (stored == null || stored.len() == 0) return false;

        foreach(alert in stored) {
            if (!alert.reported) return true;
        }
    },

    "checkImpactAlert" : function(stored, new) {
        // Each impact is a new alert, so just add it to 
        // the alerts array
        if (new != null && new.impactDetected) {
            local alert = {
                "type"     : ALERT_TYPE.SHOCK,
                "trigger"  : new.magnitude,
                "created"  : new.ts,
                "resolved" : new.ts,
                "reported" : false
            }
            stored.push(alert);
            return true;
        }

        return false;
    }

    "checkEnvAlert" : function(stored, new) {
        if (new == null) return false;

        // Returns boolean, if stored has been updated
        return (_checkTemp(stored, new) || _checkHumid(stored, new));
    },

    "checkBattAlert" : function(stored, new) {
        if (new == null) return false;

        local battAlert = new.battAlert;
        local last = getLatestAlert(stored, ALERT_TYPE.BATTERY_LOW);

        // New battery alert condition, ceate alert
        if (last == null && battAlert == ALERT_DESC.LOW) {
            // Create new alert
            local alert = {
                "type"     : ALERT_TYPE.BATTERY_LOW,
                "trigger"  : new.percent,
                "created"  : new.ts,
                "resolved" : 0,
                "reported" : false
            }
            // Add to stored alerts
            stored.push(alert);
            // Return (changes made) true
            return true;
        }

        // Alert condition resolved, update alert
        if (last != null && battAlert == ALERT_DESC.IN_RANGE) {
            // Update resolved and reported values
            local alert = {
                "type"     : last.type,
                "trigger"  : last.trigger,
                "created"  : last.created,
                "resolved" : new.ts,
                "reported" : false
            }
            stored[last.idx] = alert;
            // Return (changes made) true
            return true;
        }

        return false;
    },

    "getLatestAlert" : function(stored, type) {
        if (stored == null || stored.len() == 0) return null;

        local latest = null;
        foreach(idx, alert in stored) {
            if (alert.type == type && (latest == null || alert.created > latest.created)) {
                latest = alert;
                latest.idx <- idx;
            }
        }
        return latest;
    }, 

    "getLatestTempAlert" : function(stored) {
        if (stored == null || stored.len() == 0) return null;

        local latest = null;
        foreach(idx, alert in stored) {
            if (alert.type == ALERT_TYPE.TEMP_LOW || alert.type == ALERT_TYPE.TEMP_HIGH) {
                if (latest == null || alert.created > latest.created) {
                    latest = alert;
                    latest.idx <- idx;
                }
            }
        }
        return latest;
    },

    "getLatestHumidAlert" : function(stored) {
        if (stored == null || stored.len() == 0) return null;

        local latest = null;
        foreach(idx, alert in stored) {
            if (alert.type == ALERT_TYPE.HUMID_LOW || alert.type == ALERT_TYPE.HUMID_HIGH) {
                if (latest == null || alert.created > latest.created) {
                    latest = alert;
                    latest.idx <- idx;
                }
            }
        }
        return latest;
    },

    // Sets all reported flags to true
    "clearReported" : function(alerts) {
        if (alerts == null) return;
        foreach (idx, alert in alerts) {
            if (alert.reported == false) alerts[idx]["reported"] = true;
        }
        return alerts;
    },

    "haveUnreportedAlerts" : function(alerts) {
        if (alerts == null) return false;
        foreach (alert in alerts) {
            if (alert.reported) return true;
        }
        return false;
    },

    "_checkTemp" : function(stored, new) {
        local tempAlertDesc = new.tempAlert;
        local lastTempAlert = getLatestTempAlert(stored);

        // No temp alerts stored, but we have a new temp alert
        if (tempAlertDesc != ALERT_DESC.IN_RANGE && lastTempAlert == null) {
            // Create new alert
            local alert = {
                "type"     : (tempAlertDesc == ALERT_DESC.HIGH) ? ALERT_TYPE.TEMP_HIGH : ALERT_TYPE.TEMP_LOW,
                "trigger"  : new.temperature,
                "created"  : new.ts,
                "resolved" : 0,
                "reported" : false
            }
            // Add to stored alerts
            stored.push(alert);
            // Return (changes made) true
            return true;
        }

        // Temp alert condtion cleared, update temp alert
        if (tempAlertDesc == ALERT_DESC.IN_RANGE && lastTempAlert != null) {
            // Update resolved and reported values
            local alert = {
                "type"     : lastTempAlert.type,
                "trigger"  : lastTempAlert.trigger,
                "created"  : lastTempAlert.created,
                "resolved" : new.ts,
                "reported" : false
            }
            stored[lastTempAlert.idx] = alert;
            // Return (changes made) true
            return true;
        }

        // New alert doesn't match our current alert
        if (lastTempAlert != null && tempAlertDesc != ALERT_DESC.IN_RANGE) {
            if ((lastTempAlert.type == TEMP_HIGH && tempAlertDesc != ALERT_DESC.HIGH) ||
                (lastTempAlert.type == TEMP_LOW && tempAlertDesc != ALERT_DESC.LOW)) {
                    // Resolve stored alert if needed
                    if (lastTempAlert.resolved == 0) {
                        local updated = {
                            "type"     : lastTempAlert.type,
                            "trigger"  : lastTempAlert.trigger,
                            "created"  : lastTempAlert.created,
                            "resolved" : new.ts,
                            "reported" : false
                        }
                        stored[lastTempAlert.idx] = updated;
                    }
                    
                    // Create new alert
                    local alert = {
                        "type"     : (tempAlertDesc == ALERT_DESC.HIGH) ? ALERT_TYPE.TEMP_HIGH : ALERT_TYPE.TEMP_LOW,
                        "trigger"  : new.temperature,
                        "created"  : new.ts,
                        "resolved" : 0,
                        "reported" : false
                    };
                    // Add to stored alerts
                    stored.push(alert);
                    // Return (changes made) true
                    return true;
            }
        }

        // No alerts updated
        return false;
    },

    "_checkHumid" : function(stored, new) {
        local humidAlertDesc = new.humidAlert;
        local lastHumidAlert = getLatestHumidAlert(stored);

        // No temp alerts stored, but we have a new temp alert
        if (humidAlertDesc != ALERT_DESC.IN_RANGE && lastHumidAlert == null) {
            // Create new alert
            local alert = {
                "type"     : (humidAlertDesc == ALERT_DESC.HIGH) ? ALERT_TYPE.HUMID_HIGH : ALERT_TYPE.HUMID_LOW,
                "trigger"  : new.humidity,
                "created"  : new.ts,
                "resolved" : 0,
                "reported" : false
            }
            // Add to stored alerts
            stored.push(alert);
            // Return (changes made) true
            return true;
        }

        // Temp alert condtion cleared, update temp alert
        if (humidAlertDesc == ALERT_DESC.IN_RANGE && lastHumidAlert != null) {
            // Update resolved and reported values
            local alert = {
                "type"     : lastHumidAlert.type,
                "trigger"  : lastHumidAlert.trigger,
                "created"  : lastHumidAlert.created,
                "resolved" : new.ts,
                "reported" : false
            }
            stored[lastHumidAlert.idx] = alert;
            // Return (changes made) true
            return true;
        }

        // New alert doesn't match our current alert
        if (lastHumidAlert != null && humidAlertDesc != ALERT_DESC.IN_RANGE) {
            if ((lastHumidAlert.type == TEMP_HIGH && humidAlertDesc != ALERT_DESC.HIGH) ||
                (lastHumidAlert.type == TEMP_LOW && humidAlertDesc != ALERT_DESC.LOW)) {
                    // Resolve stored alert if needed
                    if (lastHumidAlert.resolved == 0) {
                        local updated = {
                            "type"     : lastHumidAlert.type,
                            "trigger"  : lastHumidAlert.trigger,
                            "created"  : lastHumidAlert.created,
                            "resolved" : new.ts,
                            "reported" : false
                        }
                        stored[lastHumidAlert.idx] = updated;
                    }
                    
                    // Create new alert
                    local alert = {
                        "type"     : (humidAlertDesc == ALERT_DESC.HIGH) ? ALERT_TYPE.TEMP_HIGH : ALERT_TYPE.TEMP_LOW,
                        "trigger"  : new.humidity,
                        "created"  : new.ts,
                        "resolved" : 0,
                        "reported" : false
                    }
                    // Add to stored alerts
                    stored.push(alert);
                    // Return (changes made) true
                    return true;
            }
        }

        // No alerts updated
        return false;
    }

}