import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user.dart'; // Import model yang tadi dibuat

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // FUNGSI 1: Register (Daftar Akun)
  Future<UserModel?> signUp({
    required String email,
    required String password,
    required String name,
  }) async {
    try {
      // 1. Buat user di Firebase Authentication
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      User? firebaseUser = result.user;

      if (firebaseUser != null) {
        // 2. Buat object UserModel
        UserModel newUser = UserModel(
          uid: firebaseUser.uid,
          email: email,
          name: name,
        );

        // 3. Simpan data user ke Firestore (Database)
        // Kita simpan di koleksi 'users', nama dokumennya sesuai UID
        await _firestore
            .collection('users')
            .doc(firebaseUser.uid)
            .set(newUser.toMap());

        return newUser;
      }
      return null;
    } catch (e) {
      print("Error SignUp: $e"); // Untuk debugging di console
      return null;
    }
  }

  // FUNGSI 2: Login (Masuk)
  Future<User?> signIn({required String email, required String password}) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return result.user;
    } catch (e) {
      print("Error SignIn: $e");
      return null;
    }
  }

  // FUNGSI 3: Logout (Keluar)
  Future<void> signOut() async {
    await _auth.signOut();
  }

  // Cek user yang sedang login sekarang
  User? getCurrentUser() {
    return _auth.currentUser;
  }
}