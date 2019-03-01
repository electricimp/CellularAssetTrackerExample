// Settings for a 3.7V 2000mAh battery from Adafruit and impC001 breakout
const BATT_CHARGE_VOLTAGE = 4.2;
const BATT_CURR_LIMIT     = 2000;
const FG_DES_CAP          = 2000;   // mAh
const FG_SENSE_RES        = 0.01;   // ohms
const FG_CHARGE_TERM      = 20;     // mA
const FG_EMPTY_V_TARGET   = 3.3;    // V
const FG_RECOVERY_V       = 3.88;   // V
// NOTE: Fuel gauge setting chrgV, battType are set using library constant, 
// please check these settings if updating these constants.

const BATT_STATUS_CHECK_TIMEOUT = 0.5;

// Manages Battery Monitoring  
// Dependencies: MAX17055, BQ25895M (may configure sensor i2c)
// Initializes: MAX17055, BQ25895M
class Battery {
    
    charger = null;
    fg      = null;

    fgReady = null;

    constructor(configureI2C) {
        if (configureI2C) SENSOR_I2C.configure(CLOCK_SPEED_400_KHZ);

        charger = BQ25895M(SENSOR_I2C, BATT_CHGR_ADDR);
        fg = MAX17055(SENSOR_I2C, FUEL_GAUGE_ADDR);

        // Charger default to: 4.352V and 2048mA
        charger.enable(BATT_CHARGE_VOLTAGE, BATT_CURR_LIMIT);

        local fgSettings = {
            "desCap"       : FG_DES_CAP,
            "senseRes"     : FG_SENSE_RES,
            "chrgTerm"     : FG_CHARGE_TERM,   
            "emptyVTarget" : FG_EMPTY_V_TARGET,
            "recoveryV"    : FG_RECOVERY_V,
            "chrgV"        : MAX17055_V_CHRG_4_2,
            "battType"     : MAX17055_BATT_TYPE.LiCoO2
        }
        // NOTE: Full init will only run when "power on reset alert is detected", 
        // so call this here so ready flag is always set.
        fg.init(fgSettings, function(err) {
            if (err != null) {
                ::error("Error initializing fuel gauge: " + err);
            } else {
                fgReady = true;
            }
        }.bindenv(this));
    }

    function getStatus(cb) {
        if (fgReady) {
            cb(fg.getStateOfCharge());
        } else {
            imp.wakeup(BATT_STATUS_CHECK_TIMEOUT, function() {
                getStatus(cb);
            }.bindenv(this))
        }
    }
}