// Agent Application

// Libraries 
#require "MessageManager.lib.nut:2.4.0"

@include "github:electricimp/UBloxAssistNow/AgentLibrary/UBloxAssistNow.agent.lib.nut@develop"

// Supporting files
@include __PATH__+"/../shared/Logger.shared.nut"
@include __PATH__+"/../shared/Constants.shared.nut"
@include __PATH__+"/Location.agent.nut"


// Main Application
// -----------------------------------------------------------------------

class MainController {
    
    loc = null;
    mm  = null;

    constructor() {
        // Initialize Logger 
        Logger.init(LOG_LEVEL.DEBUG);

        ::debug("Agent started...");

        // Initialize Assist Now Location Helper
        loc = Location();

        // Initialize Message Manager
        mm = MessageManager();

        // Open listeners for messages from device
        mm.on(MM_REPORT, processReport.bindenv(this));
        mm.on(MM_ASSIST, getAssist.bindenv(this));
    }

    function processReport(msg, reply) {
        local report = msg.data;

        ::debug("Recieved status update from devcie: ");
        ::debug(http.jsonencode(report));
        // Report Structure (movement, fix and battStatus only included if data was collected)
            // { 
            //   "msSinceBoot" : 37997,             // Always included
            //   "ts"          : 1551410644,        // Always included, timestamp when report sent
            //   "movement"    : true,              // Only included if movement event occured
            //   "fix"         : {                  // Only included if fix was obtained
            //       "msToFix"    : 18.197001,      // ms from boot til accurate fix 
            //       "fixType"    : 3,              // type of fix
            //       "msTo1stFix" : 9.882,          // ms from boot til first fix (not accurate)
            //       "numSats"    : 9,              // number of satellites used in fix
            //       "lon"        : "-122.1022211", // latitude
            //       "lat"        : "37.3954374",   // longitude
            //       "time"       : "2019:03:01",   // time from GPS message
            //       "accuracy"   : 9.9960003       // fix accuracy
            //   }, 
            //   "battStatus"  : {                  // Only included if info returned from fuel gauge
            //       "percent"  : 94.578125, 
            //       "capacity" : 2282 
            //   } 
            // }

        // TODO: Send device data to cloud service
    }

    function getAssist(msg, reply) {
        ::debug("Requesting online assist messages from u-blox webservice");
        loc.getOnlineAssist(function(assistMsgs) {
            ::debug("Received online assist messages from u-blox webservice");
            if (assistMsgs != null) {
                ::debug("Sending device online assist messages");
                reply(assistMsgs);
            }
        }.bindenv(this))
    }

    function getFixDescription(fixType) {
        switch(fixType) {
            case 0:
                return "no fix";
            case 1:
                return "dead reckoning only";
            case 2:
                return "2D fix";
            case 3:
                return "3D fix";
            case 4:
                return "GNSS plus dead reckoning combined";
            case 5:
                return "time-only fix";
            default: 
                return "unknown";
        }
    }

}

// Runtime
// -----------------------------------------------------------------------

// Start controller
MainController();
