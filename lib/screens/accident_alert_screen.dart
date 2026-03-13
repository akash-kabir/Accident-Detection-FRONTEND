import 'dart:async';

import 'package:flutter/material.dart';

import '../services/ble_service.dart';
import '../services/webhook_service.dart';

/// Full-screen alert shown when an accident is detected.
/// User has 10 seconds to cancel before the alert is sent.
class AccidentAlertScreen extends StatefulWidget {
  final AccidentEvent event;
  final WebhookService webhookService;

  const AccidentAlertScreen({
    super.key,
    required this.event,
    required this.webhookService,
  });

  @override
  State<AccidentAlertScreen> createState() => _AccidentAlertScreenState();
}

class _AccidentAlertScreenState extends State<AccidentAlertScreen> {
  static const int countdownSeconds = 10;

  int _remaining = countdownSeconds;
  Timer? _timer;
  bool _sending = false;
  bool _sent = false;
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  void _startCountdown() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _remaining--;
      });
      if (_remaining <= 0) {
        timer.cancel();
        _sendAlert();
      }
    });
  }

  Future<void> _sendAlert() async {
    if (_cancelled) return;
    setState(() => _sending = true);

    final success = await widget.webhookService.sendAccidentAlert(widget.event);

    if (!mounted) return;
    setState(() {
      _sending = false;
      _sent = success;
    });

    final message = success
        ? 'Emergency alert sent successfully!'
        : 'Failed to send alert. Check internet connection.';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );

    // Auto-close after showing result
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) Navigator.of(context).pop();
  }

  void _cancelAlert() {
    _timer?.cancel();
    setState(() => _cancelled = true);
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.red.shade900,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.white,
                  size: 100,
                ),
                const SizedBox(height: 24),
                const Text(
                  'ACCIDENT DETECTED',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Device: ${widget.event.deviceId}',
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
                Text(
                  'Location: ${widget.event.lat.toStringAsFixed(6)}, ${widget.event.lon.toStringAsFixed(6)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(height: 40),
                if (!_sent && !_cancelled && !_sending) ...[
                  Text(
                    'Sending alert in',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$_remaining',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 72,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'seconds',
                    style: TextStyle(color: Colors.white70, fontSize: 18),
                  ),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton(
                      onPressed: _cancelAlert,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.red.shade900,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        "I'M OK — CANCEL ALERT",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton(
                      onPressed: () {
                        _timer?.cancel();
                        _sendAlert();
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'SEND NOW',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ],
                if (_sending)
                  const Column(
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 16),
                      Text(
                        'Sending emergency alert...',
                        style: TextStyle(color: Colors.white, fontSize: 18),
                      ),
                    ],
                  ),
                if (_sent)
                  const Column(
                    children: [
                      Icon(Icons.check_circle, color: Colors.white, size: 60),
                      SizedBox(height: 16),
                      Text(
                        'Alert Sent!',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
