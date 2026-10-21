import 'category_model.dart';

class KidDeviceModel {
  final int id;
  final String name;
  final String imei;
  final String? brand;
  final double price;
  final String? image;
  final String? description;
  final String? ageRange;
  final int batteryLevel;
  final bool isOnline;
  final String status;
  final int? categoryId;
  final CategoryModel? category;

  KidDeviceModel({
    required this.id,
    required this.name,
    required this.imei,
    this.brand,
    required this.price,
    this.image,
    this.description,
    this.ageRange,
    required this.batteryLevel,
    required this.isOnline,
    required this.status,
    this.categoryId,
    this.category,
  });

  factory KidDeviceModel.fromJson(Map<String, dynamic> json) {
    return KidDeviceModel(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      imei: json['imei'] ?? '',
      brand: json['brand'],
      price: (json['price'] != null) ? (json['price'] as num).toDouble() : 0.0,
      image: json['image'],
      description: json['description'],
      ageRange: json['ageRange'],
      batteryLevel: json['batteryLevel'] ?? 100,
      isOnline: json['isOnline'] ?? false,
      status: json['status'] ?? 'Active',
      categoryId: json['categoryId'],
      category: json['category'] != null
          ? CategoryModel.fromJson(json['category'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'imei': imei,
      'brand': brand,
      'price': price,
      'image': image,
      'description': description,
      'ageRange': ageRange,
      'batteryLevel': batteryLevel,
      'isOnline': isOnline,
      'status': status,
      'categoryId': categoryId,
    };
  }
}
