class GroupModel {
  final String id;        // Kode unik grup (misal: "X7sKa9")
  final String name;      // Nama grup (misal: "Keluarga Cemara")
  final String adminId;   // UID pembuat grup
  final List<String> members; // Daftar UID semua anggota

  GroupModel({
    required this.id,
    required this.name,
    required this.adminId,
    required this.members,
  });

  // Mengubah data ke format JSON untuk disimpan ke Firestore
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'adminId': adminId,
      'members': members,
    };
  }

  // Mengambil data dari Firestore dan diubah jadi object Dart
  factory GroupModel.fromMap(Map<String, dynamic> map) {
    return GroupModel(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      adminId: map['adminId'] ?? '',
      // Trik mengubah List dynamic jadi List<String>
      members: List<String>.from(map['members'] ?? []),
    );
  }
}