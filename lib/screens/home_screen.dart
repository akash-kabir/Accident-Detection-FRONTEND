import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/api_service.dart';
import '../services/ble_service.dart';
import '../services/webhook_service.dart';
import '../widgets/glass_card.dart';
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

  BleConnectionState _connectionState = BleConnectionState.disconnected;
  bool _alertShowing = false;
  String _deviceName = '--';
  String _batteryText = '--';
  double? _lastLat;
  double? _lastLon;

  late StreamSubscription<String> _statusSub;
  late StreamSubscription<BleConnectionState> _connectionSub;
  late StreamSubscription<AccidentEvent> _accidentSub;
  late StreamSubscription<LocationEvent> _locationSub;

  @override
  void initState() {
    super.initState();

    _statusSub = _bleService.statusStream.listen((_) {});

    _connectionSub = _bleService.connectionStateStream.listen((state) {
      setState(() => _connectionState = state);
      if (state == BleConnectionState.connected) {
        _refreshDeviceDetails();
      }
      if (state == BleConnectionState.disconnected) {
        setState(() {
          _deviceName = '--';
          _batteryText = '--';
          _lastLat = null;
          _lastLon = null;
        });
      }
    });

    _accidentSub = _bleService.accidentStream.listen((event) {
      setState(() {
        _lastLat = event.lat;
        _lastLon = event.lon;
      });
      _onAccidentDetected(event);
    });

    _locationSub = _bleService.locationStream.listen((event) {
      setState(() {
        _lastLat = event.lat;
        _lastLon = event.lon;
      });
    });
  }

  Future<void> _refreshDeviceDetails() async {
    final battery = await _bleService.readBatteryLevel();
    if (!mounted) return;
    setState(() {
      _deviceName = _bleService.connectedDeviceName;
      _batteryText = battery == null ? 'Unknown' : '$battery%';
    });
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bluetooth is OFF. Please enable Bluetooth.'),
        ),
      );
      return;
    }

    await _requestPermissions();
    await _bleService.startScan();
  }

  void _onAccidentDetected(AccidentEvent event) {
    if (_alertShowing) return;
    _alertShowing = true;

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

  void _openContacts() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ContactsScreen()));
  }

  Future<void> _logout() async {
    await ApiService.logout();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _showSettingsCard() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Card(
            child: ListTile(
              leading: const Icon(Icons.logout, color: Colors.redAccent),
              title: const Text('Logout'),
              subtitle: const Text('Sign out from this device'),
              onTap: () {
                Navigator.of(ctx).pop();
                _logout();
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _statusSub.cancel();
    _connectionSub.cancel();
    _accidentSub.cancel();
    _locationSub.cancel();
    _bleService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Acci-Alert'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: _showSettingsCard,
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A212B), Color(0xFF0F1318), Color(0xFF1E171E)],
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: _connectionState == BleConnectionState.connected
                    ? _buildConnectedView()
                    : _buildBleButtonView(),
              ),
            ),
            if (_connectionState != BleConnectionState.connected)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: ElevatedButton.icon(
                    onPressed: _openContacts,
                    icon: const Icon(Icons.contacts),
                    label: const Text('Emergency Contacts'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _statusColor() {
    switch (_connectionState) {
      case BleConnectionState.disconnected:
        return Colors.redAccent;
      case BleConnectionState.scanning:
      case BleConnectionState.connecting:
        return Colors.amber;
      case BleConnectionState.connected:
        return Colors.greenAccent;
    }
  }

  String _statusLabel() {
    switch (_connectionState) {
      case BleConnectionState.disconnected:
        return 'Disconnected';
      case BleConnectionState.scanning:
        return 'Searching...';
      case BleConnectionState.connecting:
        return 'Connecting...';
      case BleConnectionState.connected:
        return 'Connected';
    }
  }

  Widget _buildBleButtonView() {
    final disabled =
        _connectionState == BleConnectionState.scanning ||
        _connectionState == BleConnectionState.connecting;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: disabled ? null : _handleScan,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 210,
              height: 210,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF232C39),
                border: Border.all(color: _statusColor(), width: 6),
                boxShadow: [
                  BoxShadow(
                    color: _statusColor().withValues(alpha: 0.28),
                    blurRadius: 18,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Icon(Icons.bluetooth, size: 110, color: _statusColor()),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            _statusLabel(),
            style: TextStyle(
              color: _statusColor(),
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Tap the button to scan and connect',
            style: TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectedView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        GlassCard(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.greenAccent.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.bluetooth_connected,
                      color: Colors.greenAccent,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Active Device',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          _deviceName,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  children: [
                    _deviceDetailBlock(
                      context,
                      icon: Icons.battery_charging_full_rounded,
                      header: 'Battery Remaining',
                      value: _batteryText,
                      valueColor: _batteryText.contains('%')
                          ? ((int.tryParse(_batteryText.replaceAll('%', '')) ??
                                        100) >
                                    20
                                ? Colors.greenAccent
                                : Colors.redAccent)
                          : null,
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Divider(height: 1),
                    ),
                    _deviceDetailBlock(
                      context,
                      icon: Icons.location_on_outlined,
                      header: 'Last Known Location',
                      value: _lastLat != null && _lastLon != null
                          ? '${_lastLat!.toStringAsFixed(5)}, ${_lastLon!.toStringAsFixed(5)}'
                          : 'Waiting for GPS...',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => _bleService.disconnect(),
          icon: const Icon(Icons.bluetooth_disabled),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.redAccent.withValues(alpha: 0.15),
            foregroundColor: Colors.redAccent,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          label: const Text(
            'Disconnect Device',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _openContacts,
          icon: const Icon(Icons.contacts),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          label: const Text(
            'Emergency Contacts',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _deviceDetailBlock(
    BuildContext context, {
    required IconData icon,
    required String header,
    required String value,
    Color? valueColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 22,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                header,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.75),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: valueColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
