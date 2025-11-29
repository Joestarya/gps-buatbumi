import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/group_model.dart';

class GroupService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _generateGroupId() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    Random rnd = Random();
    return String.fromCharCodes(Iterable.generate(
        6, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
  }

  // --- FUNGSI BARU: KELUAR DARI SEMUA GRUP LAMA ---
  // Kita pastikan user bersih dari grup manapun sebelum masuk yang baru
  Future<void> _leaveAllGroups(String userId) async {
    // Cari semua grup dimana user ini terdaftar sebagai member
    QuerySnapshot snapshot = await _firestore
        .collection('groups')
        .where('members', arrayContains: userId)
        .get();

    for (var doc in snapshot.docs) {
      // Hapus userId dari array 'members'
      await doc.reference.update({
        'members': FieldValue.arrayRemove([userId])
      });
    }
  }

  // FUNGSI 1: Create Group (Updated)
  Future<String?> createGroup(String groupName, String adminId) async {
    try {
      // STEP 1: Keluar dulu dari grup lama (FIX BUG ID NYANGKUT)
      await _leaveAllGroups(adminId);

      // STEP 2: Baru bikin grup baru
      String groupId = _generateGroupId();
      GroupModel newGroup = GroupModel(
        id: groupId,
        name: groupName,
        adminId: adminId,
        members: [adminId],
      );

      await _firestore.collection('groups').doc(groupId).set(newGroup.toMap());
      return groupId;
    } catch (e) {
      print("Error Create Group: $e");
      return null;
    }
  }

  // FUNGSI 2: Join Group (Updated)
  Future<bool> joinGroup(String groupId, String userId) async {
    try {
      DocumentReference groupRef = _firestore.collection('groups').doc(groupId);
      DocumentSnapshot doc = await groupRef.get();

      if (!doc.exists) return false;

      // STEP 1: Keluar dulu dari grup lama
      await _leaveAllGroups(userId);

      // STEP 2: Masuk grup baru
      await groupRef.update({
        'members': FieldValue.arrayUnion([userId])
      });

      return true;
    } catch (e) {
      print("Error Join Group: $e");
      return false;
    }
  }
}