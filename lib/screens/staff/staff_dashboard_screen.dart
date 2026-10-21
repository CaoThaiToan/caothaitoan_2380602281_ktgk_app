import 'package:flutter/material.dart';
import '../../models/kid_device_model.dart';
import '../../services/auth_service.dart';
import '../../services/device_service.dart';
import '../../theme/app_colors.dart';
import '../auth/login_screen.dart';

class StaffDashboardScreen extends StatefulWidget {
  const StaffDashboardScreen({super.key});

  @override
  State<StaffDashboardScreen> createState() => _StaffDashboardScreenState();
}

class _StaffDashboardScreenState extends State<StaffDashboardScreen> {
  final _deviceService = DeviceService();
  final _authService = AuthService();

  List<KidDeviceModel> _devices = [];
  bool _isLoading = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    setState(() => _isLoading = true);
    try {
      final list = await _deviceService.getDevices(search: _searchQuery);
      if (mounted) setState(() => _devices = list);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showDeviceDetail(KidDeviceModel dev) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.verified, color: Colors.orange, size: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    dev.name,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Text('Mã IMEI: ${dev.imei}', style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('Thương hiệu: ${dev.brand ?? "N/A"}'),
            const SizedBox(height: 6),
            Text('Tình trạng pin: ${dev.batteryLevel}%'),
            const SizedBox(height: 6),
            Text('Trạng thái kết nối: ${dev.isOnline ? "Đang Online" : "Ngoại tuyến"}'),
            const SizedBox(height: 6),
            Text('Danh mục: ${dev.category?.name ?? "Chưa phân loại"}'),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade800,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Thiết bị IMEI ${dev.imei} hoạt động tốt!')),
                  );
                },
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Kiểm định kỹ thuật OK'),
              ),
            ),
          ],
        ),
      ),
    );
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
        title: const Text('Staff Dashboard - Quản lý Kỹ thuật', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.orange.shade800,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadDevices),
          IconButton(icon: const Icon(Icons.logout), onPressed: _handleLogout),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.orange.shade50,
            child: Row(
              children: [
                Icon(Icons.support_agent, color: Colors.orange.shade900),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Khu vực kỹ thuật viên & nhân viên cửa hàng: Tra cứu IMEI, kiểm tra thông số sóng, pin và hỗ trợ kích hoạt thiết bị.',
                    style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Nhập tên thiết bị hoặc quét IMEI...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              onChanged: (val) {
                _searchQuery = val;
                _loadDevices();
              },
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _loadDevices,
                    child: _devices.isEmpty
                        ? const Center(child: Text('Không tìm thấy thiết bị nào'))
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            itemCount: _devices.length,
                            itemBuilder: (ctx, index) {
                              final d = _devices[index];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                child: ListTile(
                                  onTap: () => _showDeviceDetail(d),
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.orange.shade100,
                                    child: Icon(Icons.devices, color: Colors.orange.shade800),
                                  ),
                                  title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Text('IMEI: ${d.imei}\nPin: ${d.batteryLevel}% | ${d.brand ?? "N/A"}'),
                                  isThreeLine: true,
                                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}
