import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import 'api_client.dart';

class AuthService {
  final LocalAuthentication _localAuth = LocalAuthentication();

  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await ApiClient.post('authenticate/login', {
      'userName': username,
      'password': password,
    });

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data;
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['message'] ?? 'Đăng nhập thất bại!');
    }
  }

  Future<UserModel> verifyOtp(String username, String otpCode) async {
    final response = await ApiClient.post('authenticate/verify-otp', {
      'username': username,
      'otpCode': otpCode,
    });

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final token = data['token'] as String;

      // Lưu thông tin vào SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('jwt_token', token);
      await prefs.setString('username', data['username'] ?? username);
      await prefs.setString('userRole', data['role'] ?? 'Parent');
      await prefs.setString('fullName', data['fullName'] ?? '');
      await prefs.setString('userId', data['userId'] ?? '');

      return UserModel.fromJson(data, token);
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['message'] ?? 'Mã OTP không chính xác hoặc đã hết hạn!');
    }
  }

  Future<bool> register({
    required String username,
    required String email,
    required String password,
    required String fullName,
    required String role,
  }) async {
    final response = await ApiClient.post('authenticate/register', {
      'userName': username,
      'email': email,
      'password': password,
      'fullName': fullName,
      'role': role,
    });

    if (response.statusCode == 200) {
      return true;
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['message'] ?? 'Đăng ký tài khoản thất bại!');
    }
  }

  Future<UserModel?> getSavedUser() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token == null || JwtDecoder.isExpired(token)) {
      return null;
    }

    return UserModel(
      userId: prefs.getString('userId') ?? '',
      username: prefs.getString('username') ?? '',
      fullName: prefs.getString('fullName') ?? '',
      email: prefs.getString('email') ?? '',
      role: prefs.getString('userRole') ?? 'Parent',
      token: token,
    );
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
    await prefs.remove('userRole');
  }

  // Chức năng Sinh trắc học (Vân tay / FaceID) - Mục 5a & 5e
  Future<bool> authenticateWithBiometrics() async {
    try {
      final bool canAuthenticateWithBiometrics = await _localAuth.canCheckBiometrics;
      final bool canAuthenticate = canAuthenticateWithBiometrics || await _localAuth.isDeviceSupported();

      if (!canAuthenticate) {
        return false;
      }

      return await _localAuth.authenticate(
        localizedReason: 'Vui lòng xác thực vân tay hoặc khuôn mặt để đăng nhập Kids Safe',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
    } on PlatformException {
      return false;
    }
  }
}
