import 'package:flutter/material.dart';
// Import halaman Login
import '../presentation/screens/auth/login_screen.dart';
// Import halaman Map (Home kita)
import '../presentation/screens/home/map_screen.dart'; 

class AppRouter {
  static Route<dynamic> generate(RouteSettings settings) {
    switch (settings.name) {
      case '/':
        return MaterialPageRoute(builder: (_) => const MapScreen());
      case '/login':
        return MaterialPageRoute(builder: (_) => const LoginScreen());
      default:
        // Jika rute tidak ditemukan, kembalikan ke MapScreen sebagai default
        return MaterialPageRoute(builder: (_) => const MapScreen());
    }
  }
}