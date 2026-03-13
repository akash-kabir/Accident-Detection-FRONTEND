# 🚨 Acci-Alert (Accident Detection System)

Acci-Alert is a comprehensive IoT and mobile solution designed to detect vehicular collisions in real-time and instantly notify emergency contacts. Integrating an ESP32 edge device with a highly polished Flutter mobile app, this system ensures rapid response when every second counts.

## 🌟 Key Features

- **Real-Time Bluetooth Telemetry:** Connects to an ESP32 hardware device (equipped with an MPU6050) via BLE to stream real-time location and trigger data.
- **Advanced Crash Detection:** Custom ESP32 firmware utilizes jerk and magnitude analysis with confirmation debouncing to prevent false positives from normal physical bumps, accurately capturing actual impacts.
- **Automated Emergency Dispatch:** Upon crash detection, the app begins a critical 10-second countdown. If uninterrupted, a secure webhook payload is fired to an **n8n** automation pipeline.
- **Twilio SMS & WhatsApp Integration:** Contact nodes sync to the backend, enabling the n8n pipeline to automatically deliver highly visible emergency alerts and maps/GPS coordinates via Twilio.
- **Cloud-Synced Contacts:** Import phone contacts natively or add them manually. All emergency contacts, along with Telegram IDs and relationship tags, are secured via a Node.js/Express backend and Neon Serverless PostgreSQL.
- **Emergency Contrast UI:** A custom-designed dark theme featuring modern glassmorphism UI elements, carefully optimized for high visibility and immediate action during high-stress scenarios.

## 🛠️ Architecture Stack

- **Frontend:** [Flutter](https://flutter.dev) (Dart), `flutter_blue_plus` for BLE, `flutter_contacts`.
- **Backend:** Node.js, Express framework, JWT authentication.
- **Database:** Serverless PostgreSQL via [Neon](https://neon.tech/).
- **Microcontrollers (IoT):** ESP32 (C++/Arduino), MPU6050 Accelerometer/Gyroscope, BLE Characteristics (`BLE2902`).
- **Integrations:** n8n (webhook automation), Twilio (Messaging API/Sandbox).

## 📱 Platform Interface

Following the recent *Emergency Contrast* visual overhaul, Acci-Alert sports a modern, accessible interface:
- **Operations Dashboard:** A large, interactive, animated Bluetooth scanning button that transitions to a live statistics card (Device Name, Battery Level, Live Coordinates) upon successful connection.
- **Accident Dispatch Screen:** High-contrast, unmissable red/amber alert screen that safely counts down before dispatching user telemetry.
- **Contacts Management:** Clean glassmorphic cards allowing easy CRUD operations and native device phone-book mapping.

## 🚀 Getting Started

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) installed and configured on your machine.
- Node.js (for backend execution).
- A Twilio Sandbox/Account setup for messaging.
- An ESP32 flashed with the Acci-Alert firmware.

### Installation & Run

```bash
# 1. Clone the repository
git clone https://github.com/akash-kabir/Accident-Detection-FRONTEND.git

# 2. Navigate to the frontend workspace 
cd vt

# 3. Get all Flutter dependencies
flutter pub get

# 4. Run the application
flutter run
```

*Note: Ensure your ESP32 is powered on and within Bluetooth range, your Node.js backend is active (with valid `.env` config), and that your n8n workflow is listening to the webhook.*

## 🔒 Permissions Required
The mobile application will request the following on startup:
* **Bluetooth/Nearby Devices:** For ESP32 proximity location and generic scanning.
* **Location:** Required by Android/iOS to scan for BLE packets.
* **Contacts:** For importing emergency liaisons straight from the device's native address book.
