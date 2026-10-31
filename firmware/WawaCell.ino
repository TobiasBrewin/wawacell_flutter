//BLE libaries
#include <BLEDevice.h>
#include <BLEServer.h>

// HX711 pins
const int DT_PIN = 3;  // Data pin
const int SCK_PIN = 4; // Clock pin

// Calibration variables
float scale_factor = 235400;   // Value from body weight (0.64kN)
long zero_offset = 40000;    // Raw value when no load
long previous_ms = 0;
float max_force = 0;

// BLE variables
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"
BLECharacteristic *pCharacteristic;

void setup(){
  Serial.begin(115200);
  pinMode(DT_PIN, INPUT);
  pinMode(SCK_PIN, OUTPUT);
  digitalWrite(SCK_PIN, LOW);
  delay(1000);
  Serial.println("Starting");
  zero_offset = readHX711();
  startBLE();
  //calibrate();
}

void calibrate(){ //IMPORTANT: Ensure the serial is set not to send NL at end of messages
  //get zero offset
  Serial.println("Press enter to tare");
  Serial.read(); // clears serial input
  while (!Serial.available()) {} // wait for input
  zero_offset = readHX711();
  Serial.println(zero_offset);
  Serial.read(); // clear serial input

  //get scale factor
  Serial.println("Apply calibration load and enter force:");
  while (!Serial.available()) {} // wait for input
  float calibration_force = Serial.parseFloat();
  long calibration_raw = readHX711();
  Serial.println(calibration_force);
  Serial.println(calibration_raw);
  scale_factor = (float)(calibration_raw - zero_offset) / calibration_force;
  Serial.println(scale_factor);
}

void startBLE() {
  Serial.println("Starting BLE");

  if (!BLEDevice::init("WawaCell V0.1")) {
    Serial.println("BLE initialisation failed");
    return;
  }

  BLEServer *pServer = BLEDevice::createServer();
  BLEService *pService = pServer->createService(SERVICE_UUID);
  pServer->advertiseOnDisconnect(true);
  pCharacteristic = pService->createCharacteristic(
    CHARACTERISTIC_UUID, 
    BLECharacteristic::PROPERTY_READ | 
    BLECharacteristic::PROPERTY_WRITE |
    BLECharacteristic::PROPERTY_NOTIFY);

  pService->start();
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);  // functions that help with iPhone connections issue
  pAdvertising->setMaxPreferred(0x12);
  BLEDevice::startAdvertising();
  Serial.println("BLE initialised");
}

long readHX711() {
  while (digitalRead(DT_PIN) == HIGH) {}  // Wait for HX711 to become ready (DT goes LOW)
  
  // Read the 24 bit data from HX711, MSB first
  long raw = 0;
  for (int i = 0; i < 24; i++) {
    digitalWrite(SCK_PIN, HIGH);
    raw = raw << 1;
    digitalWrite(SCK_PIN, LOW);
    if (digitalRead(DT_PIN)) {
      raw++;
    }
  }

  // Pulse SCK one more time to set gain
  digitalWrite(SCK_PIN, HIGH);
  digitalWrite(SCK_PIN, LOW);

  //Convert from twos compliment
  if (raw & 0x800000) {        // if sign bit (bit 23) is set
    raw |= 0xFF000000;         // sign extend to 32 bits
  }
  return raw;
}

void loop() {
  long raw = readHX711();
  int print_interval = 1;
  float force = (float)(raw - zero_offset) / scale_factor;

  if (millis()-previous_ms > print_interval){
    previous_ms = millis();
    String output = "Force: " + String(force) + "kN";
    
    Serial.println(output);
    //pCharacteristic->setValue(output.c_str());
    pCharacteristic->setValue((uint8_t*)&force, sizeof(force));
    pCharacteristic->notify();
  }
}