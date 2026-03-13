import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Data model for an accident event received from ESP32
class AccidentEvent {
  final String deviceId;
  final double lat;
  final double lon;

  AccidentEvent({required this.deviceId, required this.lat, required this.lon});

  Map<String, dynamic> toJson() => {
    'device_id': deviceId,
    'lat': lat,
    'lon': lon,
    'accident': true,
    'severity': 'HIGH',
  };
}

/// BLE service that scans, connects, and listens to the ESP32 accident device.
class BleService {
  static const String deviceName = 'Accident_Device_ESP32';

  // ESP32 BLE UUIDs — must match your ESP32 firmware
  static const String serviceUuid = '12345678-1234-1234-1234-123456789abc';
  static const String characteristicUuid =
      'abcd1234-ab12-cd34-ef56-123456789abc';

  BluetoothDevice? _connectedDevice;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<List<int>>? _notifySubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  bool _deviceFound = false;

  final _accidentController = StreamController<AccidentEvent>.broadcast();
  final _statusController = StreamController<String>.broadcast();
  final _connectionStateController =
      StreamController<BleConnectionState>.broadcast();

  /// Stream of accident events received via BLE
  Stream<AccidentEvent> get accidentStream => _accidentController.stream;

  /// Stream of status messages for UI display
  Stream<String> get statusStream => _statusController.stream;

  /// Stream of connection state changes
  Stream<BleConnectionState> get connectionStateStream =>
      _connectionStateController.stream;

  bool get isConnected => _connectedDevice != null;

  /// Start scanning for the ESP32 device
  Future<void> startScan() async {
    _deviceFound = false;
    _statusController.add('Scanning for $deviceName...');
    _connectionStateController.add(BleConnectionState.scanning);

    // Clean up any previous scan
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    await FlutterBluePlus.stopScan();

    // First check if already bonded/system-connected from a previous session
    try {
      final systemDevices = await FlutterBluePlus.systemDevices([
        Guid(serviceUuid),
      ]);
      for (var device in systemDevices) {
        final name = device.platformName;
        if (name == deviceName || name.contains('Accident')) {
          _deviceFound = true;
          _statusController.add('Found $name in system devices!');
          _connectToDevice(device);
          return;
        }
      }
    } catch (_) {}

    _scanSubscription = FlutterBluePlus.onScanResults.listen((results) {
      for (var result in results) {
        final platformName = result.device.platformName;
        final advName = result.advertisementData.advName;
        final name = platformName.isNotEmpty ? platformName : advName;
        final serviceUuids = result.advertisementData.serviceUuids
            .map((e) => e.toString().toLowerCase())
            .toList();
        final mac = result.device.remoteId.toString();

        // Log ALL discovered devices (including unnamed) for debugging
        _statusController.add(
          'BLE: ${name.isEmpty ? "(no name)" : name} '
          '[$mac] '
          'services: $serviceUuids',
        );

        // Match by name OR by advertised service UUID
        final nameMatch = name == deviceName || name.contains('Accident');
        final uuidMatch = serviceUuids.contains(serviceUuid.toLowerCase());

        if (nameMatch || uuidMatch) {
          _deviceFound = true;
          _statusController.add('>>> Matched ESP32: $name [$mac]');
          FlutterBluePlus.stopScan();
          _scanSubscription?.cancel();
          _scanSubscription = null;
          _connectToDevice(result.device);
          return;
        }
      }
    });

    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 15),
      androidUsesFineLocation: true,
    );

    // Only show "not found" if scan completed without finding device
    if (!_deviceFound && _connectedDevice == null) {
      _statusController.add('Device not found. Try again.');
      _connectionStateController.add(BleConnectionState.disconnected);
    }
  }

  /// Connect to a discovered ESP32 device
  Future<void> _connectToDevice(BluetoothDevice device) async {
    _statusController.add('Connecting to ${device.platformName}...');
    _connectionStateController.add(BleConnectionState.connecting);

    try {
      await device.connect(timeout: const Duration(seconds: 10));
      _connectedDevice = device;

      // Listen for disconnection
      _connectionSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _statusController.add('Device disconnected.');
          _connectionStateController.add(BleConnectionState.disconnected);
          _connectedDevice = null;
          _notifySubscription?.cancel();
        }
      });

      _statusController.add('Connected! Discovering services...');
      _connectionStateController.add(BleConnectionState.connected);

      await _discoverAndSubscribe(device);
    } catch (e) {
      _statusController.add('Connection failed: $e');
      _connectionStateController.add(BleConnectionState.disconnected);
    }
  }

  /// Discover BLE services and subscribe to accident notifications
  Future<void> _discoverAndSubscribe(BluetoothDevice device) async {
    final services = await device.discoverServices();

    for (var service in services) {
      if (service.uuid.toString().toLowerCase() == serviceUuid.toLowerCase()) {
        for (var char in service.characteristics) {
          if (char.uuid.toString().toLowerCase() ==
              characteristicUuid.toLowerCase()) {
            // Enable notifications
            await char.setNotifyValue(true);
            _statusController.add('Subscribed to accident notifications.');

            _notifySubscription = char.lastValueStream.listen((value) {
              if (value.isNotEmpty) {
                _handleBleData(value);
              }
            });
            return;
          }
        }
      }
    }

    _statusController.add('Accident characteristic not found on device.');
  }

  /// Parse the BLE data from ESP32
  /// Expected format: ACCIDENT|device_id|lat|lon
  void _handleBleData(List<int> data) {
    try {
      final message = utf8.decode(data);
      _statusController.add('Received: $message');

      final parts = message.split('|');
      if (parts.length >= 4 && parts[0] == 'ACCIDENT') {
        final event = AccidentEvent(
          deviceId: parts[1],
          lat: double.parse(parts[2]),
          lon: double.parse(parts[3]),
        );
        _accidentController.add(event);
      }
    } catch (e) {
      _statusController.add('Parse error: $e');
    }
  }

  /// Disconnect from the device
  Future<void> disconnect() async {
    await _notifySubscription?.cancel();
    _notifySubscription = null;
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    try {
      await _connectedDevice?.disconnect();
    } catch (_) {}
    _connectedDevice = null;
    _deviceFound = false;
    _connectionStateController.add(BleConnectionState.disconnected);
    _statusController.add('Disconnected.');
  }

  /// Clean up all resources
  void dispose() {
    _scanSubscription?.cancel();
    _notifySubscription?.cancel();
    _connectionSubscription?.cancel();
    _accidentController.close();
    _statusController.close();
    _connectionStateController.close();
  }
}

enum BleConnectionState { disconnected, scanning, connecting, connected }
