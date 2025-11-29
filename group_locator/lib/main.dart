import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Import Auth
import 'firebase_options.dart';

// Import halaman yang sudah kita buat tadi
import 'presentation/screens/auth/login_screen.dart';
import 'presentation/screens/home/map_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const GroupLocatorApp());
}

class GroupLocatorApp extends StatelessWidget {
  const GroupLocatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Group Locator',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      // Inilah "Satpam" aplikasi kita (StreamBuilder)
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          // 1. Jika statusnya masih loading (tunggu sebentar)
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          // 2. Jika snapshot punya data (User sedang login)
          if (snapshot.hasData) {
            return const MapScreen();
          }

          // 3. Jika tidak ada data (User belum login)
          return const LoginScreen();
        },
      ),
    );
  }
}