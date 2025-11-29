import 'package:cloud_firestore/cloud_firestore.dart';

class LocationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 1. FUNGSI UPDATE LOKASI DIRI SENDIRI
  // Ini akan dipanggil setiap kali GPS HP bergerak
  Future<void> updateUserLocation(String uid, double lat, double lng) async {
    try {
      await _firestore.collection('users').doc(uid).update({
        'latitude': lat,
        'longitude': lng,
        'lastUpdated': FieldValue.serverTimestamp(), // Biar tau kapan terakhir online
      });
    } catch (e) {
      print("Error update lokasi: $e");
    }
  }

  // 2. FUNGSI MENCARI GROUP ID USER SAAT INI
  // Kita cari grup mana yang member-nya ada UID kita
  Future<String?> findMyGroupId(String uid) async {
    try {
      QuerySnapshot snapshot = await _firestore
          .collection('groups')
          .where('members', arrayContains: uid)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        return snapshot.docs.first.id;
      }
      return null;
    } catch (e) {
      print("Error cari grup: $e");
      return null;
    }
  }

  // 3. FUNGSI STREAM (CCTV) TEMAN SATU GRUP
  // Ini akan memberikan data real-time daftar member grup
  Stream<DocumentSnapshot> streamGroupData(String groupId) {
    return _firestore.collection('groups').doc(groupId).snapshots();
  }

  // 4. AMBIL DATA USER LAIN (UNTUK DAPAT NAMA & POSISI)
  Stream<QuerySnapshot> streamUsersLocation(List<String> memberIds) {
    // Ambil data user yang ID-nya ada di daftar member
    return _firestore
        .collection('users')
        .where('uid', whereIn: memberIds)
        .snapshots();
  }
}