import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/api_service.dart';
import '../services/ble_service.dart';
import '../services/webhook_service.dart';
import 'accident_alert_screen.dart';
import 'contacts_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final BleService _bleService = BleService();
  final WebhookService _webhookService = WebhookService();

  final List<String> _logs = [];
  BleConnectionState _connectionState = BleConnectionState.disconnected;
  bool _alertShowing = false;

  late StreamSubscription<String> _statusSub;
  late StreamSubscription<BleConnectionState> _connectionSub;
  late StreamSubscription<AccidentEvent> _accidentSub;

  @override
  void initState() {
    super.initState();

    _statusSub = _bleService.statusStream.listen((msg) {
      setState(() {
        _logs.add('[${_timeStamp()}] $msg');
        if (_logs.length > 100) _logs.removeAt(0);
      });
    });

    _connectionSub = _bleService.connectionStateStream.listen((state) {
      setState(() => _connectionState = state);
    });

    _accidentSub = _bleService.accidentStream.listen((event) {
      _onAccidentDetected(event);
    });
  }

  String _timeStamp() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
  }

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();
    }
  }

  Future<void> _handleScan() async {
    // Check if Bluetooth is on
    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      _addLog('Bluetooth is OFF. Please enable Bluetooth.');
      return;
    }

    await _requestPermissions();
    await _bleService.startScan();
  }

  void _onAccidentDetected(AccidentEvent event) {
    if (_alertShowing) return;
    _alertShowing = true;

    _addLog(
      '⚠️ ACCIDENT EVENT: ${event.deviceId} @ ${event.lat}, ${event.lon}',
    );

    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => AccidentAlertScreen(
              event: event,
              webhookService: _webhookService,
            ),
          ),
        )
        .then((_) => _alertShowing = false);
  }

  void _addLog(String msg) {
    setState(() {
      _logs.add('[${_timeStamp()}] $msg');
      if (_logs.length > 100) _logs.removeAt(0);
    });
  }

  @override
  void dispose() {
    _statusSub.cancel();
    _connectionSub.cancel();
    _accidentSub.cancel();
    _bleService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VT Accident Detection'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.contacts),
            tooltip: 'Emergency Contacts',
            onPressed: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const ContactsScreen()));
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () async {
              await ApiService.logout();
              if (!context.mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
          ),
          _connectionIndicator(),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          // Status card
          _buildStatusCard(),

          // Action buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed:
                        _connectionState == BleConnectionState.scanning ||
                            _connectionState == BleConnectionState.connecting
                        ? null
                        : _connectionState == BleConnectionState.connected
                        ? () => _bleService.disconnect()
                        : _handleScan,
                    icon: Icon(
                      _connectionState == BleConnectionState.connected
                          ? Icons.bluetooth_disabled
                          : Icons.bluetooth_searching,
                    ),
                    label: Text(
                      _connectionState == BleConnectionState.connected
                          ? 'Disconnect'
                          : _connectionState == BleConnectionState.scanning
                          ? 'Scanning...'
                          : _connectionState == BleConnectionState.connecting
                          ? 'Connecting...'
                          : 'Scan & Connect',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Test button — sends a fake accident event for testing
                ElevatedButton.icon(
                  onPressed: () {
                    _onAccidentDetected(
                      AccidentEvent(
                        deviceId: 'esp32_001_test',
                        lat: 20.363743,
                        lon: 85.815004,
                      ),
                    );
                  },
                  icon: const Icon(Icons.bug_report),
                  label: const Text('Test Alert'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),

          // Logs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text(
                  'Event Log',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => _logs.clear()),
                  child: const Text('Clear'),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
                borderRadius: BorderRadius.circular(12),
              ),
              child: _logs.isEmpty
                  ? const Center(
                      child: Text(
                        'No events yet. Tap "Scan & Connect" to start.',
                        style: TextStyle(color: Colors.white54),
                      ),
                    )
                  : ListView.builder(
                      reverse: true,
                      itemCount: _logs.length,
                      itemBuilder: (_, i) {
                        final log = _logs[_logs.length - 1 - i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            log,
                            style: TextStyle(
                              color: log.contains('ACCIDENT')
                                  ? Colors.redAccent
                                  : log.contains('Connected')
                                  ? Colors.greenAccent
                                  : Colors.white70,
                              fontFamily: 'monospace',
                              fontSize: 13,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _connectionIndicator() {
    Color color;
    String tooltip;

    switch (_connectionState) {
      case BleConnectionState.connected:
        color = Colors.green;
        tooltip = 'Connected';
      case BleConnectionState.scanning:
        color = Colors.orange;
        tooltip = 'Scanning';
      case BleConnectionState.connecting:
        color = Colors.yellow;
        tooltip = 'Connecting';
      case BleConnectionState.disconnected:
        color = Colors.red;
        tooltip = 'Disconnected';
    }

    return Tooltip(
      message: tooltip,
      child: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              _connectionState == BleConnectionState.connected
                  ? Icons.bluetooth_connected
                  : Icons.bluetooth_disabled,
              size: 40,
              color: _connectionState == BleConnectionState.connected
                  ? Colors.blue
                  : Colors.grey,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _connectionState == BleConnectionState.connected
                        ? 'Device Connected'
                        : 'No Device Connected',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _connectionState == BleConnectionState.connected
                        ? 'Listening for accident events...'
                        : 'Tap "Scan & Connect" to pair with ESP32',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
