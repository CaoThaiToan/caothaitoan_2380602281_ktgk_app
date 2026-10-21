import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'screens/admin/admin_dashboard_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/parent/parent_main_screen.dart';
import 'screens/staff/staff_dashboard_screen.dart';
import 'services/auth_service.dart';
import 'theme/app_colors.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("Failed to load .env: $e");
  }

  runApp(const KidsSafeApp());
}

class KidsSafeApp extends StatelessWidget {
  const KidsSafeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kids Safe-Phone',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          primary: AppColors.primary,
          secondary: AppColors.secondary,
        ),
        scaffoldBackgroundColor: AppColors.background,
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
        ),
      ),
      home: const AuthGatekeeper(),
    );
  }
}

class AuthGatekeeper extends StatefulWidget {
  const AuthGatekeeper({super.key});

  @override
  State<AuthGatekeeper> createState() => _AuthGatekeeperState();
}

class _AuthGatekeeperState extends State<AuthGatekeeper> {
  final _authService = AuthService();
  Widget? _homeWidget;

  @override
  void initState() {
    super.initState();
    _checkCurrentUser();
  }

  Future<void> _checkCurrentUser() async {
    final user = await _authService.getSavedUser();
    if (!mounted) return;

    if (user != null) {
      if (user.role.toLowerCase() == 'admin') {
        _homeWidget = const AdminDashboardScreen();
      } else if (user.role.toLowerCase() == 'staff') {
        _homeWidget = const StaffDashboardScreen();
      } else {
        _homeWidget = const ParentMainScreen();
      }
    } else {
      _homeWidget = const LoginScreen();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_homeWidget == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }
    return _homeWidget!;
  }
}
