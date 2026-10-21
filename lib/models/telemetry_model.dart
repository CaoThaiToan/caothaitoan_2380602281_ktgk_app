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

  factory TelemetryModel.fromJson(Map<String, dynamic> rawJson) {
    var json = rawJson;
    if (rawJson.containsKey('telemetry') && rawJson['telemetry'] is Map<String, dynamic>) {
      json = rawJson['telemetry'] as Map<String, dynamic>;
    } else if (rawJson.containsKey('data') && rawJson['data'] is Map<String, dynamic>) {
      json = rawJson['data'] as Map<String, dynamic>;
    }

    double parsedLat = (json['latitude'] != null) ? (json['latitude'] as num).toDouble() : 0.0;
    double parsedLng = (json['longitude'] != null) ? (json['longitude'] as num).toDouble() : 0.0;
    if (parsedLat == 0.0 && rawJson['latitude'] != null) {
      parsedLat = (rawJson['latitude'] as num).toDouble();
    }
    if (parsedLng == 0.0 && rawJson['longitude'] != null) {
      parsedLng = (rawJson['longitude'] as num).toDouble();
    }

    return TelemetryModel(
      id: json['id'] ?? (rawJson['id'] ?? 0),
      deviceId: json['deviceId'] ?? (rawJson['deviceId'] ?? 0),
      latitude: parsedLat,
      longitude: parsedLng,
      noiseDecibel: (json['noiseDecibel'] != null)
          ? (json['noiseDecibel'] as num).toDouble()
          : ((rawJson['noiseDecibel'] != null) ? (rawJson['noiseDecibel'] as num).toDouble() : 0.0),
      isFallDetected: json['isFallDetected'] ?? (rawJson['isFallDetected'] ?? false),
      isSosTriggered: json['isSosTriggered'] ?? (rawJson['isSosTriggered'] ?? false),
      alertMessage: json['alertMessage'] ?? json['sosMessage'] ?? rawJson['alertMessage'] ?? rawJson['sosMessage'],
      recordedAt: json['recordedAt'] != null
          ? DateTime.parse(json['recordedAt'])
          : (json['timestamp'] != null
              ? DateTime.parse(json['timestamp'])
              : (rawJson['timestamp'] != null ? DateTime.parse(rawJson['timestamp']) : DateTime.now())),
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
