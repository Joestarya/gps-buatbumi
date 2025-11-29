import 'package:cloud_firestore/cloud_firestore.dart';

class LocationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 1. UPDATE LOKASI
  Future<void> updateUserLocation(String uid, double lat, double lng) async {
    try {
      // GANTI .update() MENJADI .set() dengan merge: true
      // Artinya: "Kalau data user belum ada, tolong buatin sekalian!"
      await _firestore.collection('users').doc(uid).set({
        'uid': uid, // Kita pastikan UID tersimpan juga
        'latitude': lat,
        'longitude': lng,
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)); 
      
    } catch (e) {
      print("Error update lokasi: $e");
    }
  }

  // 2. CARI GROUP ID (KODE BARU: LEBIH AKURAT)
  // Kita ambil langsung dari field 'currentGroupId' di data user
  Future<String?> findMyGroupId(String uid) async {
    try {
      DocumentSnapshot userDoc = await _firestore.collection('users').doc(uid).get();
      
      if (userDoc.exists) {
        Map<String, dynamic>? data = userDoc.data() as Map<String, dynamic>?;
        // Ambil field currentGroupId, kalau gak ada balikin null
        return data?['currentGroupId']; 
      }
      return null;
    } catch (e) {
      print("Error cari grup: $e");
      return null;
    }
  }

  // 3. STREAM GROUP DATA
  Stream<DocumentSnapshot> streamGroupData(String groupId) {
    return _firestore.collection('groups').doc(groupId).snapshots();
  }

  // 4. STREAM USER LOCATIONS
  Stream<QuerySnapshot> streamUsersLocation(List<String> memberIds) {
    // Trik: Firestore 'whereIn' maksimal cuma bisa 10 item
    // Kalau membernya banyak banget bisa error, tapi buat tugas ini aman.
    if (memberIds.isEmpty) return const Stream.empty();
    
    return _firestore
        .collection('users')
        .where('uid', whereIn: memberIds)
        .snapshots();
  }
}