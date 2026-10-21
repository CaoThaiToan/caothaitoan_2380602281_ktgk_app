import 'package:flutter/material.dart';

class AppColors {
  // Bảng màu thân thiện với trẻ em và phụ huynh (Tươi sáng, an toàn, dễ nhìn)
  static const Color primary = Color(0xFF1E88E5); // Xanh dương bảo vệ
  static const Color primaryLight = Color(0xFFE3F2FD);
  static const Color secondary = Color(0xFFFF8F00); // Vàng cam ấm áp
  static const Color accent = Color(0xFF00BFA5); // Xanh ngọc tươi vui
  static const Color danger = Color(0xFFE53935); // Đỏ khẩn cấp SOS
  static const Color warning = Color(0xFFFFA000); // Cảnh báo decibel
  static const Color success = Color(0xFF43A047); // An toàn trong vùng
  
  static const Color background = Color(0xFFF8FAFC);
  static const Color cardBg = Colors.white;
  static const Color textDark = Color(0xFF1E293B);
  static const Color textMuted = Color(0xFF64748B);
}

class AppStyles {
  static final cardDecoration = BoxDecoration(
    color: AppColors.cardBg,
    borderRadius: BorderRadius.circular(16),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.04),
        blurRadius: 10,
        offset: const Offset(0, 4),
      ),
    ],
  );

  static final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(12),
  );
}
