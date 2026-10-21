import 'dart:convert';
import '../models/child_profile_model.dart';
import 'api_client.dart';

class ChildService {
  Future<List<ChildProfileModel>> getProfiles() async {
    final response = await ApiClient.get('childprofile');
    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return data.map((e) => ChildProfileModel.fromJson(e)).toList();
    }
    throw Exception('Không thể tải hồ sơ của bé');
  }

  Future<ChildProfileModel> createProfile({
    required String childName,
    required int birthYear,
    required String gender,
    String? emergencyPhone,
    String? safeZoneName,
    double? safeZoneLat,
    double? safeZoneLng,
    double? safeZoneRadiusMeters,
  }) async {
    final response = await ApiClient.post('childprofile', {
      'childName': childName,
      'birthYear': birthYear,
      'gender': gender,
      'emergencyPhone': emergencyPhone,
      'safeZoneName': safeZoneName ?? 'Trường Tiểu Học',
      'safeZoneLat': safeZoneLat ?? 10.762622,
      'safeZoneLng': safeZoneLng ?? 106.660172,
      'safeZoneRadiusMeters': safeZoneRadiusMeters ?? 500.0,
    });

    if (response.statusCode == 201 || response.statusCode == 200) {
      return ChildProfileModel.fromJson(jsonDecode(response.body));
    }
    throw Exception('Tạo hồ sơ cho bé thất bại');
  }

  // Ghép nối thiết bị qua quét mã QR IMEI (Mục 5e)
  Future<ChildProfileModel> bindDeviceWithQr(int profileId, String imei) async {
    final response = await ApiClient.post('childprofile/$profileId/bind-device', {
      'imei': imei,
    });

    if (response.statusCode == 200) {
      return ChildProfileModel.fromJson(jsonDecode(response.body));
    }
    final err = jsonDecode(response.body);
    throw Exception(err['message'] ?? 'Ghép nối thiết bị bằng mã QR thất bại');
  }

  // Cấu hình Vùng An Toàn Ảo (Geofence - Mục 6 Sáng tạo)
  Future<ChildProfileModel> updateSafeZone(
    int profileId, {
    required String safeZoneName,
    required double safeZoneLat,
    required double safeZoneLng,
    required double safeZoneRadiusMeters,
  }) async {
    final response = await ApiClient.put('childprofile/$profileId/safe-zone', {
      'safeZoneName': safeZoneName,
      'safeZoneLat': safeZoneLat,
      'safeZoneLng': safeZoneLng,
      'safeZoneRadiusMeters': safeZoneRadiusMeters,
    });

    if (response.statusCode == 200) {
      return ChildProfileModel.fromJson(jsonDecode(response.body));
    }
    throw Exception('Cập nhật vùng an toàn thất bại');
  }
}
