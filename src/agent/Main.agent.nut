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

}

// Runtime
// -----------------------------------------------------------------------

// Start controller
MainController();
