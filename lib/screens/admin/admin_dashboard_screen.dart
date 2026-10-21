import 'package:flutter/material.dart';
import '../../models/category_model.dart';
import '../../models/kid_device_model.dart';
import '../../services/auth_service.dart';
import '../../services/device_service.dart';
import '../../theme/app_colors.dart';
import '../auth/login_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _deviceService = DeviceService();
  final _authService = AuthService();

  List<CategoryModel> _categories = [];
  List<KidDeviceModel> _devices = [];
  bool _isLoading = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final cats = await _deviceService.getCategories();
      final devs = await _deviceService.getDevices(search: _searchQuery);
      if (mounted) {
        setState(() {
          _categories = cats;
          _devices = devs;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Thêm Danh mục mới
  void _showAddCategoryDialog() {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final iconCtrl = TextEditingController(text: 'devices');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thêm Danh mục mới'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Tên danh mục'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: descCtrl,
              decoration: const InputDecoration(labelText: 'Mô tả danh mục'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx);
              try {
                await _deviceService.addCategory(
                  nameCtrl.text.trim(),
                  descCtrl.text.trim(),
                  iconCtrl.text.trim(),
                );
                _loadData();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(backgroundColor: AppColors.success, content: Text('Thêm danh mục thành công!')),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Lỗi: $e')),
                );
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  // Xóa Danh mục (Kiểm thử khóa ngoại SET NULL)
  Future<void> _confirmDeleteCategory(CategoryModel category) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            SizedBox(width: 8),
            Text('Kiểm thử SET NULL'),
          ],
        ),
        content: Text(
          'Bạn có chắc muốn xóa danh mục "${category.name}"?\n\n'
          '⚠️ Ràng buộc DB: ON DELETE SET NULL.\n'
          'Các thiết bị thuộc danh mục này sẽ KHÔNG bị xóa mất, mà trường CategoryId của chúng sẽ tự động chuyển thành NULL an toàn!',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xác nhận Xóa (SET NULL)'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _deviceService.deleteCategory(category.id);
        _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: AppColors.success,
              content: Text('Đã xóa danh mục thành công! Các thiết bị liên quan đã chuyển CategoryId thành null.'),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lỗi xóa danh mục: $e')),
          );
        }
      }
    }
  }

  // Thêm Thiết bị mới
  void _showAddDeviceDialog() {
    final nameCtrl = TextEditingController();
    final imeiCtrl = TextEditingController(text: '${100000000000000 + DateTime.now().millisecondsSinceEpoch % 900000000000000}');
    final brandCtrl = TextEditingController(text: 'KidsSafe');
    final priceCtrl = TextEditingController(text: '1200000');
    final descCtrl = TextEditingController(text: 'Đồng hồ định vị định hướng an toàn');
    final ageRangeCtrl = TextEditingController(text: '5-12 tuổi');
    int? selectedCatId = _categories.isNotEmpty ? _categories.first.id : null;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Thêm Thiết bị Trẻ em mới'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Tên thiết bị')),
                TextField(controller: imeiCtrl, decoration: const InputDecoration(labelText: 'Mã IMEI (15 số)')),
                TextField(controller: brandCtrl, decoration: const InputDecoration(labelText: 'Hãng sản xuất')),
                TextField(controller: priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Giá tiền (VNĐ)')),
                TextField(controller: ageRangeCtrl, decoration: const InputDecoration(labelText: 'Độ tuổi phù hợp')),
                TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Mô tả tính năng')),
                const SizedBox(height: 10),
                DropdownButtonFormField<int?>(
                  value: selectedCatId,
                  decoration: const InputDecoration(labelText: 'Danh mục thiết bị'),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('(Không thuộc danh mục nào)')),
                    ..._categories.map((c) => DropdownMenuItem<int?>(value: c.id, child: Text(c.name))),
                  ],
                  onChanged: (v) => setDialogState(() => selectedCatId = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
              onPressed: () async {
                if (nameCtrl.text.isEmpty || imeiCtrl.text.isEmpty) return;
                Navigator.pop(ctx);
                try {
                  await _deviceService.addDevice({
                    'name': nameCtrl.text.trim(),
                    'imei': imeiCtrl.text.trim(),
                    'brand': brandCtrl.text.trim(),
                    'price': double.tryParse(priceCtrl.text) ?? 0,
                    'description': descCtrl.text.trim(),
                    'ageRange': ageRangeCtrl.text.trim(),
                    'batteryLevel': 95,
                    'isOnline': true,
                    'status': 'Active',
                    'categoryId': selectedCatId,
                  });
                  _loadData();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(backgroundColor: AppColors.success, content: Text('Thêm thiết bị thành công!')),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Lỗi thêm thiết bị: $e')),
                  );
                }
              },
              child: const Text('Lưu Thiết bị'),
            ),
          ],
        ),
      ),
    );
  }

  // Xóa Thiết bị
  Future<void> _confirmDeleteDevice(KidDeviceModel device) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text('Bạn có chắc muốn xóa thiết bị "${device.name}" (IMEI: ${device.imei})?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _deviceService.deleteDevice(device.id);
        _loadData();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(backgroundColor: AppColors.success, content: Text('Đã xóa thiết bị!')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi xóa thiết bị: $e')),
        );
      }
    }
  }

  void _handleLogout() async {
    await _authService.logout();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Admin Dashboard - Kids Safe', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Làm mới',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _handleLogout,
            tooltip: 'Đăng xuất',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.category), text: 'Danh mục (Categories)'),
            Tab(icon: Icon(Icons.devices_other), text: 'Thiết bị (KidDevices)'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildCategoriesTab(),
                _buildDevicesTab(),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _tabController.index == 0 ? Colors.red.shade700 : AppColors.primary,
        onPressed: () {
          if (_tabController.index == 0) {
            _showAddCategoryDialog();
          } else {
            _showAddDeviceDialog();
          }
        },
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildCategoriesTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.shade300),
            ),
            child: Row(
              children: const [
                Icon(Icons.info_outline, color: Colors.amber, size: 28),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Kiểm thử ràng buộc khóa ngoại: Khi xóa danh mục, các thiết bị sẽ có CategoryId = NULL thay vì bị xóa mất (ON DELETE SET NULL).',
                    style: TextStyle(fontSize: 12, color: Colors.brown, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (_categories.isEmpty)
            const Center(child: Padding(padding: EdgeInsets.all(30), child: Text('Chưa có danh mục nào')))
          else
            ..._categories.map((cat) => Card(
                  elevation: 2,
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.red.shade100,
                      child: const Icon(Icons.folder, color: Colors.red),
                    ),
                    title: Text(cat.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(cat.description ?? 'Không có mô tả'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => _confirmDeleteCategory(cat),
                    ),
                  ),
                )),
        ],
      ),
    );
  }

  Widget _buildDevicesTab() {
    return Column(
      children: [
        // Thanh tìm kiếm
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Tìm theo tên, IMEI hoặc ID...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (val) {
              _searchQuery = val;
              _loadData();
            },
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadData,
            child: _devices.isEmpty
                ? const Center(child: Text('Không tìm thấy thiết bị nào'))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _devices.length,
                    itemBuilder: (ctx, index) {
                      final dev = _devices[index];
                      return Card(
                        elevation: 2,
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundColor: dev.categoryId != null ? AppColors.primaryLight : Colors.grey.shade200,
                                child: Icon(
                                  Icons.watch_outlined,
                                  color: dev.categoryId != null ? AppColors.primary : Colors.grey,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      dev.name,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'IMEI: ${dev.imei}',
                                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontFamily: 'monospace'),
                                    ),
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 6,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: dev.categoryId != null ? Colors.blue.shade50 : Colors.red.shade50,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            dev.category?.name ?? 'Không danh mục (NULL)',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: dev.categoryId != null ? Colors.blue.shade800 : Colors.red.shade800,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.green.shade50,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            'Pin: ${dev.batteryLevel}%',
                                            style: TextStyle(fontSize: 11, color: Colors.green.shade800),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                onPressed: () => _confirmDeleteDevice(dev),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}
