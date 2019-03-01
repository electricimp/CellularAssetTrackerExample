// Hardware Abstraction Layer
// NOTE: All hardware objects are mapped to GLOBAL 
// variables. These variables are used throughout 
// the code, so vairable names should NOT be changed.

// impC001-breakout rev5.0          
LED_SPI         <- hardware.spiYJTHU;
GPS_UART        <- hardware.uartNU; 

PWR_GATE_EN     <- hardware.pinYG;   
BATT_CHGR_OTG   <- hardware.pinYU;
BATT_CHGR_INT   <- hardware.pinV;

// Sensor i2c AKA i2c0 in schematics
SENSOR_I2C      <- hardware.i2cKL;     
ACCEL_INT       <- hardware.pinW;      
TEMP_HUMID_ADDR <- 0xBE;
ACCEL_ADDR      <- 0x32;
BATT_CHGR_ADDR  <- 0xD4;
FUEL_GAUGE_ADDR <- 0x6C;   

USB_EN          <- hardware.pinYM; 
USB_LOAD_FLAG   <- hardware.pinYN; 

GROVE_I2C       <- hardware.i2cJH;
GROVE_D1        <- hardware.pinJ;
GROVE_D2        <- hardware.pinH;
GROVE_AD1       <- hardware.pinYP;
GROVE_AD2       <- hardware.pinYQ;

CLICK_SPI       <- hardware.spiPQRS;
CLICK_UART      <- hardware.uartYABCD;
CLICK_RESET     <- hardware.pinYC;
CLICK_INT       <- hardware.pinYD; 
CLICK_PWM       <- hardware.pinYT;

// Betsy's breakout board    
LOGGING_UART    <- hardware.uartDCAB;