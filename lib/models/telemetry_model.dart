class TelemetryModel {
  final int id;
  final int deviceId;
  final double latitude;
  final double longitude;
  final double noiseDecibel;
  final bool isFallDetected;
  final bool isSosTriggered;
  final String? alertMessage;
  final DateTime recordedAt;

  TelemetryModel({
    required this.id,
    required this.deviceId,
    required this.latitude,
    required this.longitude,
    required this.noiseDecibel,
    required this.isFallDetected,
    required this.isSosTriggered,
    this.alertMessage,
    required this.recordedAt,
  });

  factory TelemetryModel.fromJson(Map<String, dynamic> json) {
    return TelemetryModel(
      id: json['id'] ?? 0,
      deviceId: json['deviceId'] ?? 0,
      latitude: (json['latitude'] != null) ? (json['latitude'] as num).toDouble() : 0.0,
      longitude: (json['longitude'] != null) ? (json['longitude'] as num).toDouble() : 0.0,
      noiseDecibel: (json['noiseDecibel'] != null) ? (json['noiseDecibel'] as num).toDouble() : 0.0,
      isFallDetected: json['isFallDetected'] ?? false,
      isSosTriggered: json['isSosTriggered'] ?? false,
      alertMessage: json['alertMessage'],
      recordedAt: json['recordedAt'] != null
          ? DateTime.parse(json['recordedAt'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'deviceId': deviceId,
      'latitude': latitude,
      'longitude': longitude,
      'noiseDecibel': noiseDecibel,
      'isFallDetected': isFallDetected,
      'isSosTriggered': isSosTriggered,
      'alertMessage': alertMessage,
      'recordedAt': recordedAt.toIso8601String(),
    };
  }
}
