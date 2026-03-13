import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String baseUrl = 'https://accident-detection-backend.vercel.app';

  static const String _tokenKey = 'jwt_token';
  static const String _userKey = 'user_data';

  // ---------- Token Management ----------

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  static Future<void> saveUser(Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(user));
  }

  static Future<Map<String, dynamic>?> getUser() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_userKey);
    if (data == null) return null;
    return jsonDecode(data) as Map<String, dynamic>;
  }

  static Future<void> clearAuth() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
  }

  static Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  // ---------- Auth Headers ----------

  static Future<Map<String, String>> _authHeaders() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // ---------- Auth Endpoints ----------

  static Future<ApiResponse> register(
    String name,
    String email,
    String password,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': name, 'email': email, 'password': password}),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 201) {
        await saveToken(data['token'] as String);
        await saveUser(data['user'] as Map<String, dynamic>);
        return ApiResponse(success: true, data: data);
      }

      return ApiResponse(
        success: false,
        error: data['error'] as String? ?? 'Registration failed',
      );
    } catch (e) {
      return ApiResponse(success: false, error: 'Connection error: $e');
    }
  }

  static Future<ApiResponse> login(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        await saveToken(data['token'] as String);
        await saveUser(data['user'] as Map<String, dynamic>);
        return ApiResponse(success: true, data: data);
      }

      return ApiResponse(
        success: false,
        error: data['error'] as String? ?? 'Login failed',
      );
    } catch (e) {
      return ApiResponse(success: false, error: 'Connection error: $e');
    }
  }

  static Future<void> logout() async {
    await clearAuth();
  }

  // ---------- Device Endpoints ----------

  static Future<ApiResponse> registerDevice(
    String deviceUid,
    String name,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/devices'),
        headers: await _authHeaders(),
        body: jsonEncode({'device_uid': deviceUid, 'name': name}),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return ApiResponse(
        success: response.statusCode == 201,
        data: data,
        error: response.statusCode != 201 ? data['error'] as String? : null,
      );
    } catch (e) {
      return ApiResponse(success: false, error: 'Connection error: $e');
    }
  }

  static Future<ApiResponse> getDevices() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/devices'),
        headers: await _authHeaders(),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return ApiResponse(success: response.statusCode == 200, data: data);
    } catch (e) {
      return ApiResponse(success: false, error: 'Connection error: $e');
    }
  }

  // ---------- Contact Endpoints ----------

  static Future<ApiResponse> addContact({
    required String name,
    required String phone,
    String? telegramId,
    String? relationship,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/contacts'),
        headers: await _authHeaders(),
        body: jsonEncode({
          'name': name,
          'phone': phone,
          if (telegramId != null) 'telegram_id': telegramId,
          if (relationship != null) 'relationship': relationship,
        }),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return ApiResponse(
        success: response.statusCode == 201,
        data: data,
        error: response.statusCode != 201 ? data['error'] as String? : null,
      );
    } catch (e) {
      return ApiResponse(success: false, error: 'Connection error: $e');
    }
  }

  static Future<ApiResponse> getContacts() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/contacts'),
        headers: await _authHeaders(),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return ApiResponse(success: response.statusCode == 200, data: data);
    } catch (e) {
      return ApiResponse(success: false, error: 'Connection error: $e');
    }
  }

  static Future<ApiResponse> updateContact({
    required int id,
    required String name,
    required String phone,
    String? telegramId,
    String? relationship,
  }) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/contacts/$id'),
        headers: await _authHeaders(),
        body: jsonEncode({
          'name': name,
          'phone': phone,
          'telegram_id': telegramId,
          'relationship': relationship,
        }),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return ApiResponse(
        success: response.statusCode == 200,
        data: data,
        error: response.statusCode != 200 ? data['error'] as String? : null,
      );
    } catch (e) {
      return ApiResponse(success: false, error: 'Connection error: $e');
    }
  }

  static Future<ApiResponse> deleteContact(int id) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/contacts/$id'),
        headers: await _authHeaders(),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return ApiResponse(
        success: response.statusCode == 200,
        data: data,
        error: response.statusCode != 200 ? data['error'] as String? : null,
      );
    } catch (e) {
      return ApiResponse(success: false, error: 'Connection error: $e');
    }
  }

  // ---------- Accident Endpoints ----------

  static Future<ApiResponse> logAccident({
    required String deviceUid,
    required double lat,
    required double lon,
    bool wasCancelled = false,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/accidents'),
        headers: await _authHeaders(),
        body: jsonEncode({
          'device_uid': deviceUid,
          'lat': lat,
          'lon': lon,
          'was_cancelled': wasCancelled,
        }),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return ApiResponse(
        success: response.statusCode == 201,
        data: data,
        error: response.statusCode != 201 ? data['error'] as String? : null,
      );
    } catch (e) {
      return ApiResponse(success: false, error: 'Connection error: $e');
    }
  }

  static Future<ApiResponse> getAccidents() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/accidents'),
        headers: await _authHeaders(),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return ApiResponse(success: response.statusCode == 200, data: data);
    } catch (e) {
      return ApiResponse(success: false, error: 'Connection error: $e');
    }
  }
}

class ApiResponse {
  final bool success;
  final Map<String, dynamic>? data;
  final String? error;

  ApiResponse({required this.success, this.data, this.error});
}
