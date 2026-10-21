import 'dart:convert';
import '../models/category_model.dart';
import '../models/kid_device_model.dart';
import 'api_client.dart';

class DeviceService {
  // Lấy danh mục
  Future<List<CategoryModel>> getCategories() async {
    final response = await ApiClient.get('category');
    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return data.map((e) => CategoryModel.fromJson(e)).toList();
    }
    throw Exception('Không thể tải danh sách danh mục');
  }

  // Thêm danh mục mới (Admin)
  Future<CategoryModel> addCategory(String name, String? description, String? icon) async {
    final response = await ApiClient.post('category', {
      'name': name,
      'description': description,
      'icon': icon,
    });
    if (response.statusCode == 201 || response.statusCode == 200) {
      return CategoryModel.fromJson(jsonDecode(response.body));
    }
    throw Exception('Thêm danh mục thất bại');
  }

  // Xóa danh mục (Kiểm thử khóa ngoại SET NULL)
  Future<bool> deleteCategory(int id) async {
    final response = await ApiClient.delete('category/$id');
    return response.statusCode == 204 || response.statusCode == 200;
  }

  // Lấy danh sách thiết bị kèm tìm kiếm
  Future<List<KidDeviceModel>> getDevices({String? search, int? categoryId}) async {
    String query = '';
    final List<String> params = [];
    if (search != null && search.isNotEmpty) {
      params.add('search=${Uri.encodeComponent(search)}');
    }
    if (categoryId != null && categoryId > 0) {
      params.add('categoryId=$categoryId');
    }
    if (params.isNotEmpty) {
      query = '?${params.join('&')}';
    }

    final response = await ApiClient.get('kiddevice$query');
    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return data.map((e) => KidDeviceModel.fromJson(e)).toList();
    }
    throw Exception('Không thể tải danh sách thiết bị');
  }

  // Thêm thiết bị mới (Admin / Staff)
  Future<KidDeviceModel> addDevice(Map<String, dynamic> data) async {
    final response = await ApiClient.post('kiddevice', data);
    if (response.statusCode == 201 || response.statusCode == 200) {
      return KidDeviceModel.fromJson(jsonDecode(response.body));
    }
    final err = jsonDecode(response.body);
    throw Exception(err['message'] ?? 'Thêm thiết bị thất bại');
  }

  // Cập nhật thiết bị
  Future<KidDeviceModel> updateDevice(int id, Map<String, dynamic> data) async {
    final response = await ApiClient.put('kiddevice/$id', data);
    if (response.statusCode == 200) {
      return KidDeviceModel.fromJson(jsonDecode(response.body));
    }
    throw Exception('Cập nhật thiết bị thất bại');
  }

  // Xóa thiết bị
  Future<bool> deleteDevice(int id) async {
    final response = await ApiClient.delete('kiddevice/$id');
    return response.statusCode == 204 || response.statusCode == 200;
  }
}
