import 'dart:convert';
import '../models/telemetry_model.dart';
import 'api_client.dart';

class TelemetryService {
  Future<TelemetryModel?> getLatestTelemetry(int deviceId) async {
    final response = await ApiClient.get('telemetry/latest/$deviceId');
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return TelemetryModel.fromJson(data);
    }
    return null;
  }

  // Gửi tọa độ GPS + mức tiếng ồn decibel + trạng thái té ngã
  Future<TelemetryModel> sendTelemetry({
    required int deviceId,
    required double latitude,
    required double longitude,
    required double noiseDecibel,
    required bool isFallDetected,
    bool isSosTriggered = false,
    String? alertMessage,
  }) async {
    final response = await ApiClient.post('telemetry', {
      'deviceId': deviceId,
      'latitude': latitude,
      'longitude': longitude,
      'noiseDecibel': noiseDecibel,
      'isFallDetected': isFallDetected,
      'isSosTriggered': isSosTriggered,
      'alertMessage': alertMessage,
    });

    if (response.statusCode == 201 || response.statusCode == 200) {
      return TelemetryModel.fromJson(jsonDecode(response.body));
    }
    throw Exception('Gửi dữ liệu giám sát thất bại');
  }

  // Kích hoạt SOS khẩn cấp (Mục 6 - Tính năng mới sáng tạo)
  Future<TelemetryModel> triggerSos({
    required int deviceId,
    required double latitude,
    required double longitude,
    required double noiseDecibel,
  }) async {
    final response = await ApiClient.post('telemetry/sos', {
      'deviceId': deviceId,
      'latitude': latitude,
      'longitude': longitude,
      'noiseDecibel': noiseDecibel,
    });

    if (response.statusCode == 200) {
      return TelemetryModel.fromJson(jsonDecode(response.body));
    }
    throw Exception('Kích hoạt báo động SOS thất bại');
  }
}
