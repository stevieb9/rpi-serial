#include <SoftwareSerial.h>
#include <millisDelay.h>
#include <stdint.h>
#include <stdlib.h>

extern "C" {
    #include "crc16.h"
}
const byte HC12RxdPin = 8;                  // Recieve Pin on HC12
const byte HC12TxdPin = 9;                  // Transmit Pin on HC12

const unsigned long interval = 2000;
unsigned long startTime = millis();

SoftwareSerial HC12(HC12TxdPin, HC12RxdPin); // Create Software Serial Port

void setup() {
    Serial.begin(9600);                       // Open serial port to computer
    HC12.begin(9600);                         // Open serial port to HC12
}

void loop() {
    if (millis () - startTime >= interval) {
        char *test = "hello";

        Serial.print(F("["));
        Serial.print(test);
        Serial.print(F("]"));
        Serial.println(crc16(test, 5));

        HC12.write('[');

        for (int i=0; i<5; i++){
            HC12.write(test[i]);
        }

        HC12.write(']');

        unsigned short crc = crc16(test, 5);

        uint8_t msb = crc >> 8;
        uint8_t lsb = crc & 0xFF;

        Serial.print("msb: ");
        Serial.println(msb);
        Serial.print("lsb: ");
        Serial.println(lsb);

        HC12.write(msb);
        HC12.write(lsb);

        startTime = millis();
    }
}