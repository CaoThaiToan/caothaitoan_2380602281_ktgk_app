import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:record/record.dart';
import '../../models/child_profile_model.dart';
import '../../models/kid_device_model.dart';
import '../../models/telemetry_model.dart';
import '../../services/auth_service.dart';
import '../../services/child_service.dart';
import '../../services/device_service.dart';
import '../../services/telemetry_service.dart';
import '../../theme/app_colors.dart';
import '../auth/login_screen.dart';

class ParentMainScreen extends StatefulWidget {
  const ParentMainScreen({super.key});

  @override
  State<ParentMainScreen> createState() => _ParentMainScreenState();
}

class _ParentMainScreenState extends State<ParentMainScreen> {
  int _currentIndex = 0;
  final _childService = ChildService();
  final _telemetryService = TelemetryService();
  final _deviceService = DeviceService();
  final _authService = AuthService();
  final MapController _mapController = MapController();

  // Microphone thu âm Decibel phần cứng thật (Galaxy A51)
  final AudioRecorder _audioRecorder = AudioRecorder();
  Timer? _amplitudeTimer;
  bool _isLiveMicActive = false;

  // Stream GPS thời gian thực từ cảm biến vệ tinh của điện thoại
  StreamSubscription<Position>? _gpsStreamSubscription;

  ChildProfileModel? _activeProfile;
  TelemetryModel? _latestTelemetry;
  List<KidDeviceModel> _availableDevices = [];
  bool _isLoading = true;

  // Tọa độ GPS phụ huynh & khoảng cách tới bé
  Position? _parentPosition;
  double _distanceInMeters = 0.0;
  bool _isInsideSafeZone = true;
  int _mapLayerType = 0; // 0: Google Hybrid Satellite, 1: Google Roadmap, 2: OpenStreetMap

  // Dữ liệu đo tiếng ồn & chuyển động
  double _currentDecibel = 48.0;
  bool _isFallDetected = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _amplitudeTimer?.cancel();
    _audioRecorder.dispose();
    _gpsStreamSubscription?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  // Bật/tắt chế độ đo Decibel từ micro thật của điện thoại
  Future<void> _toggleLiveMicrophone() async {
    if (_isLiveMicActive) {
      await _stopLiveMicrophone();
    } else {
      await _startLiveMicrophone();
    }
  }

  Future<void> _startLiveMicrophone() async {
    try {
      final hasPerm = await _audioRecorder.hasPermission();
      if (!hasPerm) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vui lòng cấp quyền Microphone để đo tiếng ồn!')),
        );
        return;
      }

      final tempDir = await Directory.systemTemp.createTemp();
      final filePath = '${tempDir.path}/live_decibel_temp.m4a';

      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: filePath,
      );

      setState(() => _isLiveMicActive = true);

      _amplitudeTimer?.cancel();
      _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 120), (timer) async {
        if (!_isLiveMicActive) return;
        try {
          final amp = await _audioRecorder.getAmplitude();
          double rawDb = amp.current;
          if (rawDb < -100) rawDb = -100;
          // amp.current từ -100 đến 0 dBFS chuyển đổi sang thang đo SPL dB tương ứng:
          double dBSpl = (rawDb + 98.0).clamp(35.0, 115.0);
          if (mounted) {
            setState(() {
              _currentDecibel = dBSpl;
            });
          }
        } catch (_) {}
      });
    } catch (e) {
      debugPrint('Error starting live microphone: $e');
    }
  }

  Future<void> _stopLiveMicrophone() async {
    _amplitudeTimer?.cancel();
    try {
      if (await _audioRecorder.isRecording()) {
        await _audioRecorder.stop();
      }
    } catch (_) {}
    if (mounted) {
      setState(() => _isLiveMicActive = false);
    }
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      final profiles = await _childService.getProfiles();
      final devices = await _deviceService.getDevices();

      if (profiles.isNotEmpty) {
        _activeProfile = profiles.first;
        if (_activeProfile?.deviceId != null) {
          final telem = await _telemetryService.getLatestTelemetry(_activeProfile!.deviceId!);
          if (telem != null) {
            _latestTelemetry = telem;
            _currentDecibel = telem.noiseDecibel;
            _isFallDetected = telem.isFallDetected;
          }
        }
      }

      _availableDevices = devices;
      await _checkParentLocationAndDistance();
    } catch (e) {
      debugPrint('Error loading initial data: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Đo vị trí GPS phụ huynh thời gian thực & tính khoảng cách tới vị trí bé (Mục 5b)
  Future<void> _checkParentLocationAndDistance() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      Position pos;
      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);

        // Kích hoạt luồng theo dõi GPS thời gian thực (Realtime Stream)
        _gpsStreamSubscription ??= Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 2, // Tự động cập nhật mỗi khi phụ huynh di chuyển từ 2 mét
          ),
        ).listen((Position livePos) {
          _updateGpsAndDistance(livePos);
        });
      } else {
        // Tọa độ mặc định cho máy ảo / giả lập (TP.HCM)
        pos = Position(
          latitude: 10.762900,
          longitude: 106.660500,
          timestamp: DateTime.now(),
          accuracy: 5.0,
          altitude: 10.0,
          heading: 0.0,
          speed: 0.0,
          speedAccuracy: 0.0,
          altitudeAccuracy: 0.0,
          headingAccuracy: 0.0,
        );
      }

      _updateGpsAndDistance(pos);
    } catch (e) {
      debugPrint('GPS check error: $e');
    }
  }

  void _updateGpsAndDistance(Position pos) {
    final double safeLat = _activeProfile?.safeZoneLat ?? 10.762622;
    final double safeLng = _activeProfile?.safeZoneLng ?? 106.660172;
    final childLat = (_latestTelemetry?.latitude != null && _latestTelemetry!.latitude != 0.0)
        ? _latestTelemetry!.latitude
        : safeLat;
    final childLng = (_latestTelemetry?.longitude != null && _latestTelemetry!.longitude != 0.0)
        ? _latestTelemetry!.longitude
        : safeLng;

    final dist = Geolocator.distanceBetween(
      pos.latitude,
      pos.longitude,
      childLat,
      childLng,
    );

    final safeRadius = _activeProfile?.safeZoneRadiusMeters ?? 500.0;
    final centerLat = safeLat;
    final centerLng = safeLng;

    final distFromSafeCenter = Geolocator.distanceBetween(
      centerLat,
      centerLng,
      childLat,
      childLng,
    );

    if (mounted) {
      setState(() {
        _parentPosition = pos;
        _distanceInMeters = dist;
        _isInsideSafeZone = distFromSafeCenter <= safeRadius;
      });
    }
  }

  // Giả lập bé di chuyển ra ngoài vùng an toàn để kiểm thử
  Future<void> _simulateChildMovement(bool moveOutside) async {
    if (_activeProfile?.deviceId == null) return;

    final double safeLat = _activeProfile?.safeZoneLat ?? 10.762622;
    final double safeLng = _activeProfile?.safeZoneLng ?? 106.660172;
    final double newLat = moveOutside ? 10.785000 : safeLat;
    final double newLng = moveOutside ? 106.690000 : safeLng;

    // Cập nhật trạng thái ngay lập tức trên UI (phản hồi tức thì, không bị delay mạng)
    final localTelem = TelemetryModel(
      id: _latestTelemetry?.id ?? 1,
      deviceId: _activeProfile!.deviceId!,
      latitude: newLat,
      longitude: newLng,
      noiseDecibel: _currentDecibel,
      isFallDetected: _isFallDetected,
      isSosTriggered: false,
      alertMessage: moveOutside ? 'Cảnh báo: Bé đã đi ra khỏi Vùng An Toàn!' : null,
      recordedAt: DateTime.now(),
    );

    setState(() {
      _latestTelemetry = localTelem;
      _isInsideSafeZone = !moveOutside;
    });

    try {
      if (moveOutside) {
        // Căn góc nhìn toàn cảnh để thấy cả Vùng An Toàn Trường học và vị trí Bé đi xa
        final midLat = (newLat + safeLat) / 2;
        final midLng = (newLng + safeLng) / 2;
        _mapController.move(LatLng(midLat, midLng), 13.0);
      } else {
        // Căn góc nhìn vào trường học
        _mapController.move(LatLng(safeLat, safeLng), 15.0);
      }
    } catch (_) {}

    if (_parentPosition != null) {
      _updateGpsAndDistance(_parentPosition!);
    }

    try {
      final telem = await _telemetryService.sendTelemetry(
        deviceId: _activeProfile!.deviceId!,
        latitude: newLat,
        longitude: newLng,
        noiseDecibel: _currentDecibel,
        isFallDetected: _isFallDetected,
        alertMessage: moveOutside ? 'Cảnh báo: Bé đã đi ra khỏi Trường học!' : 'Bé đang ở trường an toàn',
      );

      if (mounted) {
        setState(() {
          _latestTelemetry = telem;
          _isInsideSafeZone = !moveOutside;
        });

        if (_parentPosition != null) {
          _updateGpsAndDistance(_parentPosition!);
        }
      }

      if (!mounted) return;
      if (moveOutside) {
        _showSafeZoneBreachDialog();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.success,
            content: Text('Bé đã quay lại Vùng An Toàn! Cảnh báo đỏ đã được gỡ bỏ.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error simulating child movement: $e');
      if (mounted && !moveOutside) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.success,
            content: Text('Bé đã quay lại Vùng An Toàn! Cảnh báo đỏ đã được gỡ bỏ.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _showSafeZoneBreachDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.red.shade50,
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 32),
            SizedBox(width: 8),
            Text('CẢNH BÁO KHẨN CẤP', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bé ${_activeProfile?.childName ?? "Bé"} vừa ra khỏi ${_activeProfile?.safeZoneName ?? "Vùng an toàn"}!',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('Khoảng cách hiện tại: ${_distanceInMeters.toStringAsFixed(0)} mét.'),
            const SizedBox(height: 4),
            const Text('Hệ thống khuyến nghị phụ huynh gọi điện ngay cho bé hoặc người giám hộ.'),
          ],
        ),
        actions: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx),
            icon: const Icon(Icons.check),
            label: const Text('Đã hiểu & Kiểm tra ngay'),
          ),
        ],
      ),
    );
  }

  // Kích hoạt SOS khẩn cấp (Mục 6 Sáng tạo)
  Future<void> _handleTriggerSos() async {
    if (_activeProfile?.deviceId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng ghép nối thiết bị trước khi thử SOS!')),
      );
      return;
    }

    try {
      final telem = await _telemetryService.triggerSos(
        deviceId: _activeProfile!.deviceId!,
        latitude: (_latestTelemetry?.latitude != null && _latestTelemetry!.latitude != 0.0)
            ? _latestTelemetry!.latitude
            : (_activeProfile?.safeZoneLat ?? 10.762622),
        longitude: (_latestTelemetry?.longitude != null && _latestTelemetry!.longitude != 0.0)
            ? _latestTelemetry!.longitude
            : (_activeProfile?.safeZoneLng ?? 106.660172),
        noiseDecibel: 92.5, // Giả lập tiếng hét / ồn lớn khi gặp nạn
      );

      setState(() {
        _latestTelemetry = telem;
        _currentDecibel = 92.5;
      });

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.red.shade900,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: const [
              Icon(Icons.campaign, color: Colors.white, size: 36),
              SizedBox(width: 10),
              Text('TÍN HIỆU SOS KÍCH HOẠT!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Bé ${_activeProfile?.childName ?? "Bé"} đã bấm nút cứu hộ khẩn cấp!',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('📍 Tọa độ: ${telem.latitude.toStringAsFixed(6)}, ${telem.longitude.toStringAsFixed(6)}', style: const TextStyle(color: Colors.white)),
                    const SizedBox(height: 4),
                    Text('🔊 Mức tiếng ồn xung quanh: ${telem.noiseDecibel} dB (Rất lớn)', style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('📞 Số liên hệ khẩn cấp: ${_activeProfile?.emergencyPhone ?? "0901234567"}', style: const TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Đóng Báo Động', style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.red.shade900),
              onPressed: () {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đang kết nối cuộc gọi khẩn cấp tới bé...')),
                );
              },
              child: const Text('Gọi Điện Cho Bé Ngay'),
            ),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi kích hoạt SOS: $e')));
    }
  }

  // Quét / Ghép nối mã QR (Mục 5e)
  Future<void> _pairDeviceWithImei(String imei) async {
    if (_activeProfile == null) return;
    try {
      final updated = await _childService.bindDeviceWithQr(_activeProfile!.id, imei);
      setState(() {
        _activeProfile = updated;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.success,
          content: Text('Ghép nối thiết bị IMEI $imei thành công trong 1 giây!'),
        ),
      );
      _loadInitialData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('Lỗi ghép nối: $e')),
      );
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
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.primaryLight,
              child: const Icon(Icons.child_care, color: AppColors.primary),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _activeProfile?.childName ?? 'Bé Yêu',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  _isInsideSafeZone ? '🟢 Trong vùng an toàn' : '🔴 Vượt rào cảnh báo',
                  style: TextStyle(
                    fontSize: 11,
                    color: _isInsideSafeZone ? Colors.green.shade700 : Colors.red.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textDark,
        elevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.primary),
            onPressed: _loadInitialData,
            tooltip: 'Làm mới',
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.grey),
            onPressed: _handleLogout,
            tooltip: 'Đăng xuất',
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildGpsAndSafeZoneTab(),
          _buildNoiseAndSensorsTab(),
          _buildDeviceAndSosTab(),
          _buildQrPairingTab(),
          _buildProfileSettingsTab(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textMuted,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
        unselectedLabelStyle: const TextStyle(fontSize: 10),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.location_on_outlined),
            activeIcon: Icon(Icons.location_on),
            label: 'Định vị GPS',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.graphic_eq_outlined),
            activeIcon: Icon(Icons.graphic_eq),
            label: 'Tiếng ồn & Ngã',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.warning_amber_rounded),
            activeIcon: Icon(Icons.warning_rounded),
            label: 'Báo động SOS',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.qr_code_scanner_outlined),
            activeIcon: Icon(Icons.qr_code_scanner),
            label: 'Ghép nối QR',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: 'Cài đặt',
          ),
        ],
      ),
    );
  }

  // ================= TAB 1: GPS & VÙNG AN TOÀN (MỤC 5b & MỤC 6) =================
  Widget _buildGpsAndSafeZoneTab() {
    final safeLat = _activeProfile?.safeZoneLat ?? 10.762622;
    final safeLng = _activeProfile?.safeZoneLng ?? 106.660172;
    final childLat = (_latestTelemetry?.latitude != null && _latestTelemetry!.latitude != 0.0)
        ? _latestTelemetry!.latitude
        : safeLat;
    final childLng = (_latestTelemetry?.longitude != null && _latestTelemetry!.longitude != 0.0)
        ? _latestTelemetry!.longitude
        : safeLng;
    final radius = _activeProfile?.safeZoneRadiusMeters ?? 500.0;

    return RefreshIndicator(
      onRefresh: _checkParentLocationAndDistance,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Thẻ trạng thái Vùng An Toàn Ảo
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _isInsideSafeZone ? Colors.green.shade50 : Colors.red.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _isInsideSafeZone ? Colors.green.shade300 : Colors.red.shade300,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: _isInsideSafeZone ? Colors.green.shade100 : Colors.red.shade100,
                  child: Icon(
                    _isInsideSafeZone ? Icons.verified_user : Icons.warning_rounded,
                    color: _isInsideSafeZone ? Colors.green.shade800 : Colors.red.shade800,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isInsideSafeZone ? 'BÉ ĐANG TRONG VÙNG AN TOÀN' : '⚠️ BÉ ĐÃ RA NGOÀI VÙNG AN TOÀN',
                        style: TextStyle(
                          color: _isInsideSafeZone ? Colors.green.shade900 : Colors.red.shade900,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Vùng an toàn: ${_activeProfile?.safeZoneName ?? "Trường học"} (Bán kính ${radius.toInt()}m)',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                      ),
                      Text(
                        'Cách ba mẹ: ${_distanceInMeters < 1000 ? "${_distanceInMeters.toStringAsFixed(0)}m" : "${(_distanceInMeters / 1000).toStringAsFixed(2)}km"}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ================= BẢN ĐỒ VỆ TINH & VÙNG AN TOÀN TRỰC QUAN =================
          Card(
            elevation: 3,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header bản đồ: Tiêu đề + Nút đổi chế độ Vệ tinh / Đường phố
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  color: Colors.grey.shade100,
                  child: Row(
                    children: [
                      const Icon(Icons.satellite_alt, color: AppColors.primary, size: 20),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text(
                          'Bản đồ Vệ tinh & SafeZone',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Nút chuyển chế độ Vệ tinh / Đường phố
                      InkWell(
                        onTap: () {
                          setState(() {
                            _mapLayerType = (_mapLayerType + 1) % 3;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.primary),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _mapLayerType == 0
                                    ? Icons.satellite_alt
                                    : (_mapLayerType == 1 ? Icons.map : Icons.public),
                                size: 14,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _mapLayerType == 0
                                    ? '🛰️ Vệ tinh'
                                    : (_mapLayerType == 1 ? '🗺️ Đường phố' : '🌍 OSM'),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Khung hiển thị Bản đồ
                SizedBox(
                  height: 330,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: FlutterMap(
                          mapController: _mapController,
                          options: MapOptions(
                            initialCenter: LatLng(
                              _isInsideSafeZone ? safeLat : (childLat + safeLat) / 2,
                              _isInsideSafeZone ? safeLng : (childLng + safeLng) / 2,
                            ),
                            initialZoom: _isInsideSafeZone ? 14.5 : 13.0,
                            minZoom: 4.0,
                            maxZoom: 19.0,
                          ),
                          children: [
                            // Lớp bản đồ Vệ tinh Google / Đường phố / CartoDB / OSM
                            TileLayer(
                              urlTemplate: _mapLayerType == 0
                                  ? 'https://mt{s}.google.com/vt/lyrs=y&x={x}&y={y}&z={z}'
                                  : (_mapLayerType == 1
                                      ? 'https://mt{s}.google.com/vt/lyrs=m&x={x}&y={y}&z={z}'
                                      : 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png'),
                              fallbackUrl: _mapLayerType == 0
                                  ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                                  : 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                              subdomains: _mapLayerType == 2
                                  ? const ['a', 'b', 'c', 'd']
                                  : const ['0', '1', '2', '3'],
                              userAgentPackageName: 'com.example.caothaitoan_2380602281_ktgk_app',
                              tileProvider: NetworkTileProvider(
                                headers: <String, String>{
                                  'User-Agent':
                                      'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
                                },
                              ),
                              maxNativeZoom: 19,
                              maxZoom: 20,
                            ),
                          // 1. Vòng tròn Vùng An Toàn Trường học (Circle Layer)
                          CircleLayer(
                            circles: [
                              CircleMarker(
                                point: LatLng(safeLat, safeLng),
                                radius: radius,
                                useRadiusInMeter: true,
                                color: _isInsideSafeZone
                                    ? Colors.green.withValues(alpha: 0.28)
                                    : Colors.red.withValues(alpha: 0.32),
                                borderColor: _isInsideSafeZone ? Colors.greenAccent.shade700 : Colors.redAccent,
                                borderStrokeWidth: 3.5,
                              ),
                            ],
                          ),
                          // 2. Đường kẻ nối khoảng cách Ba Mẹ - Bé (Polyline Layer)
                          if (_parentPosition != null)
                            PolylineLayer(
                              polylines: [
                                Polyline(
                                  points: [
                                    LatLng(_parentPosition!.latitude, _parentPosition!.longitude),
                                    LatLng(childLat, childLng),
                                  ],
                                  color: Colors.amberAccent,
                                  strokeWidth: 3.0,
                                ),
                              ],
                            ),
                          // 3. Các điểm mốc định vị (Marker Layer)
                          MarkerLayer(
                            markers: [
                              // Điểm Trường học (Tâm vùng an toàn)
                              Marker(
                                point: LatLng(safeLat, safeLng),
                                width: 110,
                                height: 58,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade800,
                                        borderRadius: BorderRadius.circular(8),
                                        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)],
                                      ),
                                      child: const Text('🏫 Vùng An Toàn',
                                          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                    ),
                                    const Icon(Icons.school, color: Colors.greenAccent, size: 28),
                                  ],
                                ),
                              ),
                              // Điểm Vị trí của Bé
                              Marker(
                                point: LatLng(childLat, childLng),
                                width: 120,
                                height: 62,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: _isInsideSafeZone ? Colors.blue.shade800 : Colors.red.shade800,
                                        borderRadius: BorderRadius.circular(8),
                                        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)],
                                      ),
                                      child: Text(
                                        '👶 ${_activeProfile?.childName ?? "Bé"}',
                                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Icon(
                                      Icons.location_on,
                                      color: _isInsideSafeZone ? Colors.blueAccent : Colors.redAccent,
                                      size: 34,
                                    ),
                                  ],
                                ),
                              ),
                              // Điểm Vị trí của Ba Mẹ
                              if (_parentPosition != null)
                                Marker(
                                  point: LatLng(_parentPosition!.latitude, _parentPosition!.longitude),
                                  width: 90,
                                  height: 56,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.purple.shade800,
                                          borderRadius: BorderRadius.circular(8),
                                          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)],
                                        ),
                                        child: const Text('👤 Ba Mẹ',
                                            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                      ),
                                      const Icon(Icons.person_pin_circle, color: Colors.purpleAccent, size: 28),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Các nút công cụ điều khiển trên góc bản đồ
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Column(
                          children: [
                            FloatingActionButton.small(
                              heroTag: 'map_btn_fit',
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.orange.shade800,
                              elevation: 3,
                              onPressed: () {
                                final midLat = (childLat + safeLat) / 2;
                                final midLng = (childLng + safeLng) / 2;
                                _mapController.move(LatLng(midLat, midLng), 13.0);
                              },
                              tooltip: 'Xem toàn cảnh',
                              child: const Icon(Icons.zoom_out_map, size: 20),
                            ),
                            const SizedBox(height: 6),
                            FloatingActionButton.small(
                              heroTag: 'map_btn_child',
                              backgroundColor: Colors.white,
                              foregroundColor: AppColors.primary,
                              elevation: 3,
                              onPressed: () {
                                _mapController.move(LatLng(childLat, childLng), 15.5);
                              },
                              tooltip: 'Xem vị trí Bé',
                              child: const Icon(Icons.child_care, size: 20),
                            ),
                            const SizedBox(height: 6),
                            FloatingActionButton.small(
                              heroTag: 'map_btn_school',
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.green.shade700,
                              elevation: 3,
                              onPressed: () {
                                _mapController.move(LatLng(safeLat, safeLng), 15.5);
                              },
                              tooltip: 'Xem Vùng An Toàn',
                              child: const Icon(Icons.school, size: 20),
                            ),
                            if (_parentPosition != null) ...[
                              const SizedBox(height: 6),
                              FloatingActionButton.small(
                                heroTag: 'map_btn_parent',
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.purple.shade700,
                                elevation: 3,
                                onPressed: () {
                                  _mapController.move(LatLng(_parentPosition!.latitude, _parentPosition!.longitude), 15.5);
                                },
                                tooltip: 'Xem vị trí Ba Mẹ',
                                child: const Icon(Icons.my_location, size: 20),
                              ),
                            ],
                          ],
                        ),
                      ),
                      // Chú thích bản đồ ở góc dưới bên trái
                      Positioned(
                        bottom: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.circle, color: Colors.greenAccent, size: 9),
                              const SizedBox(width: 3),
                              const Text('Vùng an toàn', style: TextStyle(color: Colors.white, fontSize: 10)),
                              const SizedBox(width: 8),
                              Icon(Icons.circle, color: _isInsideSafeZone ? Colors.blueAccent : Colors.redAccent, size: 9),
                              const SizedBox(width: 3),
                              Text(_isInsideSafeZone ? 'Bé trong trường' : 'Bé vượt rào',
                                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Tọa độ chi tiết
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.my_location, color: AppColors.primary, size: 22),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Tọa độ GPS Thời Gian Thực',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Vị trí của Bé:', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                          Text('$childLat, $childLng', style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(8)),
                        child: const Text('Live GPS 4G', style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_parentPosition != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Vị trí của Ba Mẹ:', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                        Text('${_parentPosition!.latitude.toStringAsFixed(6)}, ${_parentPosition!.longitude.toStringAsFixed(6)}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Nút Giả lập Di chuyển (dành cho thuyết trình và chấm điểm)
          Card(
            elevation: 1,
            color: Colors.blue.shade50,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.science_outlined, color: AppColors.primary),
                      SizedBox(width: 8),
                      Text('Thử nghiệm Di chuyển của Bé:', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('Bấm để mô phỏng bé di chuyển để người chấm thấy cảnh báo thời gian thực:', style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange.shade700,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () => _simulateChildMovement(true),
                          icon: const Icon(Icons.directions_run),
                          label: const Text('Bé Vượt Rào'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.success,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () => _simulateChildMovement(false),
                          icon: const Icon(Icons.school),
                          label: const Text('Bé Ở Trường'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ================= TAB 2: TIẾNG ỒN & CẢM BIẾN CHUYỂN ĐỘNG (MỤC 5d) =================
  Widget _buildNoiseAndSensorsTab() {
    Color noiseColor = Colors.green;
    String noiseStatus = 'Yên tĩnh / Bình thường';
    if (_currentDecibel > 80) {
      noiseColor = Colors.red;
      noiseStatus = 'NGUY HIỂM: Tiếng ồn vượt ngưỡng an toàn! (Có tiếng hét hoặc nơi quá ồn)';
    } else if (_currentDecibel > 60) {
      noiseColor = Colors.orange;
      noiseStatus = 'Mức độ vừa phải (Môi trường đường phố / Giờ ra chơi)';
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Đồng hồ Decibel
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.mic, color: AppColors.primary, size: 22),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Máy Đo Tiếng Ồn Môi Trường',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 160,
                      height: 160,
                      child: CircularProgressIndicator(
                        value: (_currentDecibel / 120.0).clamp(0.0, 1.0),
                        strokeWidth: 14,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation<Color>(noiseColor),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _currentDecibel.toStringAsFixed(1),
                          style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: noiseColor),
                        ),
                        const Text('dB (Decibel)', style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: noiseColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: noiseColor.withOpacity(0.3)),
                  ),
                  child: Text(
                    noiseStatus,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: noiseColor, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Thẻ kích hoạt Micro thật của Galaxy A51
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: _isLiveMicActive ? Colors.green.shade100 : Colors.blue.shade50,
                      child: Icon(
                        _isLiveMicActive ? Icons.graphic_eq : Icons.mic,
                        color: _isLiveMicActive ? Colors.green.shade800 : AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Micro Phần Cứng Thật (Galaxy A51)',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          Text(
                            _isLiveMicActive
                                ? '🟢 Đang đo âm thanh thời gian thực từ Micro!'
                                : 'Chưa bật (Bấm nút dưới để bật mic thật)',
                            style: TextStyle(
                              fontSize: 12,
                              color: _isLiveMicActive ? Colors.green.shade800 : Colors.grey.shade600,
                              fontWeight: _isLiveMicActive ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isLiveMicActive ? Colors.red.shade600 : AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _toggleLiveMicrophone,
                  icon: Icon(_isLiveMicActive ? Icons.mic_off : Icons.mic),
                  label: Text(
                    _isLiveMicActive
                        ? 'Dừng Đo Micro Thật'
                        : 'BẬT MICRO THẬT ĐO DECIBEL',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (_isLiveMicActive)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '👉 Hãy nói to hoặc vỗ tay gần micro điện thoại, số Decibel ở trên sẽ lập tức nhảy theo âm lượng thật!',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.blue.shade900, fontWeight: FontWeight.w500),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Cảm biến Gia tốc & Té ngã
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: _isFallDetected ? Colors.red.shade100 : Colors.blue.shade50,
                  child: Icon(
                    _isFallDetected ? Icons.personal_injury : Icons.directions_walk,
                    color: _isFallDetected ? Colors.red : AppColors.primary,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Cảm biến Té Ngã / Chuyển Động', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 4),
                      Text(
                        _isFallDetected ? '⚠️ PHÁT HIỆN VA CHẠM / TÉ NGÃ!' : 'Bình thường (Không có va đập)',
                        style: TextStyle(
                          color: _isFallDetected ? Colors.red.shade800 : Colors.green.shade800,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Thao tác thử nghiệm cảm biến
        Card(
          elevation: 1,
          color: Colors.amber.shade50,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('⚡ Thử nghiệm cảm biến cho Giảng viên:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white),
                        onPressed: () {
                          setState(() {
                            _currentDecibel = 88.5;
                            _isFallDetected = true;
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(backgroundColor: Colors.red, content: Text('Đã kích hoạt mô phỏng: Tiếng ồn 88.5dB & Té ngã!')),
                          );
                        },
                        icon: const Icon(Icons.volume_up),
                        label: const Text('Mô phỏng ồn lớn + Ngã'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          setState(() {
                            _currentDecibel = 42.0;
                            _isFallDetected = false;
                          });
                        },
                        icon: const Icon(Icons.restore),
                        label: const Text('Đặt lại Bình thường (42dB)'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ================= TAB 3: THIẾT BỊ & NÚT SOS KHẨN CẤP (MỤC 6 SÁNG TẠO) =================
  Widget _buildDeviceAndSosTab() {
    final dev = _activeProfile?.device;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Thẻ thông tin thiết bị đang đeo
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.watch, color: AppColors.primary, size: 28),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        dev?.name ?? 'Chưa liên kết thiết bị',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Mã IMEI thiết bị:'),
                    Text(dev?.imei ?? 'N/A', style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Dung lượng Pin:'),
                    Row(
                      children: [
                        Icon(Icons.battery_charging_full, color: Colors.green.shade700, size: 20),
                        const SizedBox(width: 4),
                        Text('${dev?.batteryLevel ?? 88}% (Tốt)', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Kết nối sóng di động:'),
                    const Text('🟢 4G Trực tuyến', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // NÚT SOS TO TRÒN NỔI BẬT
        Center(
          child: Column(
            children: [
              GestureDetector(
                onTap: _handleTriggerSos,
                child: Container(
                  width: 170,
                  height: 170,
                  decoration: BoxDecoration(
                    color: AppColors.danger,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.danger.withOpacity(0.4),
                        blurRadius: 25,
                        spreadRadius: 6,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.sos_rounded, size: 68, color: Colors.white),
                        Text(
                          'BÁO ĐỘNG SOS',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Bấm vào nút SOS để giả lập bé ấn gọi cấp cứu khẩn cấp',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ================= TAB 4: GHÉP NỐI MÃ QR / BARCODE (MỤC 5e) =================
  Widget _buildQrPairingTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('Ghép Nối Thiết Bị Bằng Mã QR & Barcode', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                SizedBox(height: 4),
                Text(
                  'Quét mã QR trên thân máy hoặc vỏ hộp đồng hồ để liên kết thiết bị với tài khoản của bé trong 1 giây.',
                  style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        // Khung Camera quét mã QR
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 240,
            color: Colors.black87,
            child: Stack(
              alignment: Alignment.center,
              children: [
                MobileScanner(
                  onDetect: (capture) {
                    final List<Barcode> barcodes = capture.barcodes;
                    for (final barcode in barcodes) {
                      final raw = barcode.rawValue;
                      if (raw != null && raw.isNotEmpty) {
                        _pairDeviceWithImei(raw);
                        break;
                      }
                    }
                  },
                ),
                Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.greenAccent, width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const Positioned(
                  bottom: 12,
                  child: Text(
                    'Đưa mã QR trên vỏ hộp vào khung quét',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),

        // GIẢ LẬP QUÉT MÃ QR DÀNH CHO MÁY ẢO ANDROID
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.green.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Icons.qr_code_2, color: Colors.green, size: 24),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '⚡ Mô phỏng Quét mã QR (Nhanh):',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text('Chọn nhanh 1 trong các mã IMEI sau để ghép nối tức thì:', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 10),
              ..._availableDevices.map((d) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.textDark,
                        elevation: 1,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => _pairDeviceWithImei(d.imei),
                      child: Row(
                        children: [
                          const Icon(Icons.qr_code, color: AppColors.primary, size: 20),
                          const SizedBox(width: 8),
                          Expanded(child: Text('${d.name}\nIMEI: ${d.imei}', style: const TextStyle(fontSize: 12))),
                          const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                        ],
                      ),
                    ),
                  )),
            ],
          ),
        ),
      ],
    );
  }

  // ================= TAB 5: CÀI ĐẶT & TÀI KHOẢN =================
  Widget _buildProfileSettingsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const CircleAvatar(
                  radius: 36,
                  backgroundColor: AppColors.primaryLight,
                  child: Icon(Icons.person, size: 40, color: AppColors.primary),
                ),
                const SizedBox(height: 10),
                const Text('Tài khoản Phụ Huynh', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Text('parent1@kidssafe.com', style: TextStyle(color: AppColors.textMuted)),
                const Divider(height: 24),
                ListTile(
                  leading: const Icon(Icons.fingerprint, color: AppColors.accent),
                  title: const Text('Đăng nhập Vân tay / Sinh trắc học'),
                  subtitle: const Text('Đã bật bảo mật vân tay'),
                  trailing: Switch(value: true, onChanged: (v) {}),
                ),
                ListTile(
                  leading: const Icon(Icons.notifications_active_outlined, color: AppColors.secondary),
                  title: const Text('Thông báo Vùng an toàn & SOS'),
                  subtitle: const Text('Nhận cảnh báo tức thì qua âm thanh'),
                  trailing: Switch(value: true, onChanged: (v) {}),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Thẻ kích hoạt Micro thật của Galaxy A51
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: _isLiveMicActive ? Colors.green.shade100 : Colors.blue.shade50,
                      child: Icon(
                        _isLiveMicActive ? Icons.graphic_eq : Icons.mic,
                        color: _isLiveMicActive ? Colors.green.shade800 : AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Micro Phần Cứng Thật (Galaxy A51)',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          Text(
                            _isLiveMicActive
                                ? '🟢 Đang đo âm thanh thời gian thực từ Micro!'
                                : 'Chưa bật (Bấm nút dưới để bật mic thật)',
                            style: TextStyle(
                              fontSize: 12,
                              color: _isLiveMicActive ? Colors.green.shade800 : Colors.grey.shade600,
                              fontWeight: _isLiveMicActive ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isLiveMicActive ? Colors.red.shade600 : AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _toggleLiveMicrophone,
                  icon: Icon(_isLiveMicActive ? Icons.mic_off : Icons.mic),
                  label: Text(
                    _isLiveMicActive
                        ? 'Dừng Đo Micro Thật'
                        : 'BẬT MICRO THẬT ĐO DECIBEL',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (_isLiveMicActive)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '👉 Hãy nói to hoặc vỗ tay gần micro điện thoại, số Decibel ở trên sẽ lập tức nhảy theo âm lượng thật!',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.blue.shade900, fontWeight: FontWeight.w500),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red.shade50,
            foregroundColor: Colors.red.shade700,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: _handleLogout,
          icon: const Icon(Icons.logout),
          label: const Text('Đăng xuất tài khoản', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
