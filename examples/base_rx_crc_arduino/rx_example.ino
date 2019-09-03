#include <SoftwareSerial.h>
#include <millisDelay.h>
#include <stdint.h>
#include <stdlib.h>

extern "C" {
    #include "crc16.h"
}

#define SERIAL_DEBUG    1

#define PIR_PIN         5

const char *pirOff      = "50";
const char *pirOn       = "51";

const byte rxPin = 8;
const byte txPin = 9;

const unsigned long interval = 2000;
unsigned long startTime = millis();

const char startChar = '[';
const char endChar   = ']';

SoftwareSerial hc12(txPin, rxPin);

void setup() {
    Serial.begin(9600);
    hc12.begin(9600);
}

void loop() {

    if (millis () - startTime >= interval) {

        if (digitalRead(PIR_PIN))
             hc12Send(pirOn, strlen(pirOn));
        else
            hc12Send(pirOff, strlen(pirOff));

        startTime = millis();
    }
}

void hc12Send (char *data, uint8_t len){

    unsigned short crc = crc16(data, len);
    uint8_t msb = crc >> 8;
    uint8_t lsb = crc & 0xFF;

    if (SERIAL_DEBUG){
        displaySerial(data, len, msb, lsb);
    }

    hc12.write(startChar);

    for (int i=0; i<len; i++){
        hc12.write(data[i]);
    }

    hc12.write(endChar);

    hc12.write(msb);
    hc12.write(lsb);
}
void displaySerial (char *data, uint8_t len, uint8_t msb, uint8_t lsb){

    Serial.print(startChar);
    Serial.print(data);
    Serial.print(endChar);
    Serial.println(crc16(data, len));

    Serial.print(F("msb: "));
    Serial.println(msb);
    Serial.print(F("lsb: "));
    Serial.println(lsb);
}