import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_service.dart';
import 'ble_service.dart';

/// Service to send accident events to the n8n webhook.
class WebhookService {
  static const String webhookUrl =
      'https://akash2405359.app.n8n.cloud/webhook/accident';

  /// Posts accident data to n8n webhook.
  /// Includes user_id so n8n fetches the correct user's contacts.
  Future<bool> sendAccidentAlert(AccidentEvent event) async {
    try {
      // Get the logged-in user's ID
      final user = await ApiService.getUser();
      final userId = user?['id'];

      final payload = {
        ...event.toJson(),
        if (userId != null) 'user_id': userId,
      };

      final body = jsonEncode(payload);
      debugPrint('Webhook POST $webhookUrl');
      debugPrint('Webhook body: $body');

      final response = await http.post(
        Uri.parse(webhookUrl),
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      debugPrint('Webhook response: ${response.statusCode} ${response.body}');
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('Webhook error: $e');
      return false;
    }
  }
}
