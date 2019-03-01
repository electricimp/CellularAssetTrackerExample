// Basic Logging Class

// Confiure Logging UART on device
const LOGGING_UART_BAUD_RATE = 115200;
if ("LOGGING_UART" in getroottable()) {
    LOGGING_UART.configure(LOGGING_UART_BAUD_RATE, 8, PARITY_NONE, 1, NO_CTSRTS);
    uartLoggingConfigured <- true;
}

enum LOG_LEVEL {
    DEBUG,
    INFO,
    ERROR
}

Logger <- {

    "level"   : LOG_LEVEL.DEBUG,
    "isAgent" : null, 

    "init" : function(_level, _cm = null) {
        // Set log level
        level = _level;
        // Store environment lookup 
        if (isAgent == null) isAgent = _isAgent();
        // Update isConnected to use connection manager
        if (_cm != null) {
            _isConnected = function() {
                return _cm.isConnected();
            }
        }
    },

    "debug" : function(msg) {
        if (level <= LOG_LEVEL.DEBUG) {
            _log("[DEBUG]: " + msg.tostring());
        }
    },

    "info" : function(msg) {
        if (level <= LOG_LEVEL.INFO) {
            _log("[INFO]: " + msg.tostring());
        }
    },

    "error" : function(msg) {
        if (level <= LOG_LEVEL.ERROR) {
            _log("[ERROR]: " + msg.tostring());
        }
    },

    "_isConnected" : function() {
        return server.isconnected();
    },

    "_isAgent" : function() {
        return (imp.environment() == ENVIRONMENT_AGENT);
    },

    "_log" : function(msg, err = false) {
        // Configure isAgent if needed 
        if (isAgent == null) isAgent = _isAgent();

        // Log message
        if (isAgent) {
            (err) ? server.error(msg) : server.log(msg);
        } else {
            if (_isConnected()) {
                (err) ? server.error(msg) : server.log(msg);
            }
            if (uartLoggingConfigured) {
                local d = date();
                local ts = format("%04d-%02d-%02d %02d:%02d:%02d", d.year, d.month+1, d.day, d.hour, d.min, d.sec);
                LOGGING_UART.write(ts + " " + msg + "\n\r");
            }
        }
    },
}

// Create global logging functions
// Note: "error", "debug" and "log" are 
// all global variables and should not be used as 
// variable names in other places
debug <- Logger.debug.bindenv(Logger);
log <- Logger.info.bindenv(Logger);
error <- Logger.error.bindenv(Logger);
