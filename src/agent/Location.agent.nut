const UBLOX_ASSISTNOW_TOKEN = "@{UBLOX_ASSISTNOW_TOKEN}";

// Manages u-blox Assist Now Logic
// Dependencies: UBloxAssistNow(agent)
// Initializes: UBloxAssistNow(agent)
class Location {
    
    assist             = null;

    constructor() {
        assist  = UBloxAssistNow(UBLOX_ASSISTNOW_TOKEN);
    }

    function getOnlineAssist(onResp) {
        local assistOnlineParams = {
            "gnss"     : ["gps", "glo"],
            "datatype" : ["eph", "alm", "aux"]
        };

        assist.requestOnline(assistOnlineParams, function(err, resp) {
            local assistData = null;
            if (err != null) {
                ::error("Online req error: " + err);
            } else {
                ::debug("Received AssistNow Online. Data length: " + resp.body.len());
                assistData = resp.body;
            }
            onResp(assistData);
        }.bindenv(this));
    }

}