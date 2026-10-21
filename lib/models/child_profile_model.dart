import 'kid_device_model.dart';

class ChildProfileModel {
  final int id;
  final String childName;
  final int birthYear;
  final String gender;
  final String? avatar;
  final String parentId;
  final int? deviceId;
  final KidDeviceModel? device;
  final String? emergencyPhone;
  final String? safeZoneName;
  final double? safeZoneLat;
  final double? safeZoneLng;
  final double? safeZoneRadiusMeters;

  ChildProfileModel({
    required this.id,
    required this.childName,
    required this.birthYear,
    required this.gender,
    this.avatar,
    required this.parentId,
    this.deviceId,
    this.device,
    this.emergencyPhone,
    this.safeZoneName,
    this.safeZoneLat,
    this.safeZoneLng,
    this.safeZoneRadiusMeters,
  });

  factory ChildProfileModel.fromJson(Map<String, dynamic> json) {
    return ChildProfileModel(
      id: json['id'] ?? 0,
      childName: json['childName'] ?? '',
      birthYear: json['birthYear'] ?? 2018,
      gender: json['gender'] ?? 'Nam',
      avatar: json['avatar'],
      parentId: json['parentId'] ?? '',
      deviceId: json['deviceId'],
      device: json['device'] != null ? KidDeviceModel.fromJson(json['device']) : null,
      emergencyPhone: json['emergencyPhone'],
      safeZoneName: json['safeZoneName'] ?? 'Trường Tiểu Học',
      safeZoneLat: (json['safeZoneLat'] != null) ? (json['safeZoneLat'] as num).toDouble() : 10.762622,
      safeZoneLng: (json['safeZoneLng'] != null) ? (json['safeZoneLng'] as num).toDouble() : 106.660172,
      safeZoneRadiusMeters: (json['safeZoneRadiusMeters'] != null)
          ? (json['safeZoneRadiusMeters'] as num).toDouble()
          : 500.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'childName': childName,
      'birthYear': birthYear,
      'gender': gender,
      'avatar': avatar,
      'parentId': parentId,
      'deviceId': deviceId,
      'emergencyPhone': emergencyPhone,
      'safeZoneName': safeZoneName,
      'safeZoneLat': safeZoneLat,
      'safeZoneLng': safeZoneLng,
      'safeZoneRadiusMeters': safeZoneRadiusMeters,
    };
  }
}
