class UserModel {
  final String uid;
  final String email;
  final String name;
  final String? photoUrl; // Tanda tanya (?) artinya boleh kosong/null

  UserModel({
    required this.uid,
    required this.email,
    required this.name,
    this.photoUrl,
  });

  // FUNGSI 1: toMap
  // Mengubah object Dart menjadi format Map (JSON) agar bisa disimpan ke Firebase
  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'name': name,
      'photoUrl': photoUrl,
    };
  }

  // FUNGSI 2: fromMap
  // Mengambil data dari Firebase (Map/JSON) dan mengubahnya kembali menjadi object Dart
  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['uid'] ?? '',
      email: map['email'] ?? '',
      name: map['name'] ?? 'User',
      photoUrl: map['photoUrl'],
    );
  }
}