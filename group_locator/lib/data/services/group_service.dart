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

  // Helper: Update data User biar dia ingat dia lagi di grup mana dan daftar grup yang sudah join
  Future<void> _updateUserGroups(String userId, String groupId) async {
    await _firestore.collection('users').doc(userId).update({
      'currentGroupId': groupId,
      'joinedGroups': FieldValue.arrayUnion([groupId]), // Tambahkan ke list jika belum ada
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
      await _updateUserGroups(adminId, groupId);

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
      await _updateUserGroups(userId, groupId);

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

  // FUNGSI 4: Ambil daftar grup yang sudah di-join user
  Future<List<String>> getJoinedGroups(String userId) async {
    try {
      DocumentSnapshot doc = await _firestore.collection('users').doc(userId).get();
      if (!doc.exists) return [];
      Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
      List<dynamic> joined = data['joinedGroups'] ?? [];
      return List<String>.from(joined);
    } catch (e) {
      print("Error getJoinedGroups: $e");
      return [];
    }
  }

  // FUNGSI 5: Switch ke grup lain (yang sudah di-join)
  Future<bool> switchGroup(String userId, String groupId) async {
    try {
      // Pastikan user sudah join grup ini
      List<String> joined = await getJoinedGroups(userId);
      if (!joined.contains(groupId)) return false;

      await _firestore.collection('users').doc(userId).update({
        'currentGroupId': groupId,
      });
      return true;
    } catch (e) {
      print("Error switchGroup: $e");
      return false;
    }
  }

  // FUNGSI 6: Leave Group
  Future<bool> leaveGroup(String groupId, String userId) async {
    try {
      DocumentReference groupRef = _firestore.collection('groups').doc(groupId);
      DocumentSnapshot doc = await groupRef.get();

      if (!doc.exists) return false;

      // 1. Hapus user dari members grup
      await groupRef.update({
        'members': FieldValue.arrayRemove([userId])
      });

      // 2. Hapus grup dari joinedGroups user
      await _firestore.collection('users').doc(userId).update({
        'joinedGroups': FieldValue.arrayRemove([groupId])
      });

      // 3. Jika user sedang aktif di grup ini, set currentGroupId ke null atau switch ke grup lain
      DocumentSnapshot userDoc = await _firestore.collection('users').doc(userId).get();
      if (userDoc.exists) {
        Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
        if (userData['currentGroupId'] == groupId) {
          // Set ke null atau cari grup lain
          List<String> remainingGroups = await getJoinedGroups(userId);
          remainingGroups.remove(groupId); // Sudah dihapus di atas, tapi untuk safety
          String? newCurrent = remainingGroups.isNotEmpty ? remainingGroups.first : null;
          await _firestore.collection('users').doc(userId).update({
            'currentGroupId': newCurrent,
          });
        }
      }

      return true;
    } catch (e) {
      print("Error leaveGroup: $e");
      return false;
    }
  }

  // FUNGSI 7: Remove Member (hanya admin yang bisa)
  Future<bool> removeMember(String groupId, String adminId, String memberIdToRemove) async {
    try {
      DocumentReference groupRef = _firestore.collection('groups').doc(groupId);
      DocumentSnapshot doc = await groupRef.get();

      if (!doc.exists) return false;

      GroupModel group = GroupModel.fromMap(doc.data() as Map<String, dynamic>);

      // Periksa apakah adminId adalah admin grup
      if (group.adminId != adminId) {
        print("Error: Only admin can remove members");
        return false;
      }

      // Tidak bisa hapus diri sendiri
      if (memberIdToRemove == adminId) {
        print("Error: Admin cannot remove themselves");
        return false;
      }

      // 1. Hapus member dari members grup
      await groupRef.update({
        'members': FieldValue.arrayRemove([memberIdToRemove])
      });

      // 2. Hapus grup dari joinedGroups member
      await _firestore.collection('users').doc(memberIdToRemove).update({
        'joinedGroups': FieldValue.arrayRemove([groupId])
      });

      // 3. Jika member sedang aktif di grup ini, set currentGroupId ke null atau switch ke grup lain
      DocumentSnapshot userDoc = await _firestore.collection('users').doc(memberIdToRemove).get();
      if (userDoc.exists) {
        Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
        if (userData['currentGroupId'] == groupId) {
          List<String> remainingGroups = await getJoinedGroups(memberIdToRemove);
          remainingGroups.remove(groupId);
          String? newCurrent = remainingGroups.isNotEmpty ? remainingGroups.first : null;
          await _firestore.collection('users').doc(memberIdToRemove).update({
            'currentGroupId': newCurrent,
          });
        }
      }

      return true;
    } catch (e) {
      print("Error removeMember: $e");
      return false;
    }
  }

  // FUNGSI 8: Get Group Info (untuk mendapatkan adminId dll)
  Future<GroupModel?> getGroupInfo(String groupId) async {
    try {
      DocumentSnapshot doc = await _firestore.collection('groups').doc(groupId).get();
      if (!doc.exists) return null;
      return GroupModel.fromMap(doc.data() as Map<String, dynamic>);
    } catch (e) {
      print("Error getGroupInfo: $e");
      return null;
    }
  }

  // FUNGSI 9: Get User Name by UID
  Future<String> getUserName(String uid) async {
    try {
      DocumentSnapshot doc = await _firestore.collection('users').doc(uid).get();
      if (!doc.exists) return 'Unknown User';
      Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
      return data['name'] ?? 'Unknown User';
    } catch (e) {
      print("Error getUserName: $e");
      return 'Unknown User';
    }
  }
}