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

  // Helper: Update data User biar dia ingat dia lagi di grup mana
  Future<void> _updateUserCurrentGroup(String userId, String groupId) async {
    await _firestore.collection('users').doc(userId).update({
      'currentGroupId': groupId, // <--- INI KUNCINYA
    });
  }

  // FUNGSI 1: Create Group
  Future<String?> createGroup(String groupName, String adminId) async {
    try {
      String groupId = _generateGroupId();
      GroupModel newGroup = GroupModel(
        id: groupId,
        name: groupName,
        adminId: adminId,
        members: [adminId],
      );

      // 1. Simpan Grup Baru
      await _firestore.collection('groups').doc(groupId).set(newGroup.toMap());
      
      // 2. Tandai di User bahwa ini grup TERBARU-nya
      await _updateUserCurrentGroup(adminId, groupId);

      return groupId;
    } catch (e) {
      print("Error Create Group: $e");
      return null;
    }
  }

  // FUNGSI 2: Join Group
  Future<bool> joinGroup(String groupId, String userId) async {
    try {
      DocumentReference groupRef = _firestore.collection('groups').doc(groupId);
      DocumentSnapshot doc = await groupRef.get();

      if (!doc.exists) {
          print("---------------------------------------");
          print("GAGAL JOIN! Dokumen tidak ditemukan.");
          print("ID yang dicari HP: '$groupId'"); 
          print("---------------------------------------");
          return false; 
        }
      // 1. Masukkan user ke member grup
      await groupRef.update({
        'members': FieldValue.arrayUnion([userId])
      });

      // 2. Tandai di User bahwa ini grup TERBARU-nya
      await _updateUserCurrentGroup(userId, groupId);

      return true;
    } catch (e) {
      print("Error Join Group: $e");
      return false;
    }
  }

  // FUNGSI 3: Ambil daftar member grup
  Future<List<String>> getGroupMembers(String groupId) async {
    try {
      DocumentSnapshot doc = await _firestore.collection('groups').doc(groupId).get();
      if (!doc.exists) return [];
      GroupModel g = GroupModel.fromMap(doc.data() as Map<String, dynamic>);
      return g.members;
    } catch (e) {
      print("Error getGroupMembers: $e");
      return [];
    }
  }
}