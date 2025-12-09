import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../data/services/group_service.dart';
import '../../../data/services/location_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class GroupScreen extends StatefulWidget {
  const GroupScreen({super.key});

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> {
  final TextEditingController _groupNameController = TextEditingController();
  final TextEditingController _groupIdController = TextEditingController();
  final GroupService _groupService = GroupService();
  final LocationService _locationService = LocationService();
  final String _currentUserId = FirebaseAuth.instance.currentUser!.uid;
  bool _isLoading = false;
  String? _myGroupId;
  List<String> _joinedGroups = [];

  @override
  void initState() {
    super.initState();
    _loadMyGroup();
  }

  Future<void> _loadMyGroup() async {
    String? groupId = await _locationService.findMyGroupId(_currentUserId);
    List<String> joined = await _groupService.getJoinedGroups(_currentUserId);
    if (!mounted) return;
    setState(() {
      _myGroupId = groupId;
      _joinedGroups = joined;
    });
  }

  // --- LOGIKA BUAT GRUP ---
  void _handleCreateGroup() async {
    // Validasi: Nama grup tidak boleh kosong
    if (_groupNameController.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Isi nama grup dulu!')));
        return;
    }

    setState(() => _isLoading = true);

    // Fungsi createGroup di service sudah pakai Random, jadi setiap dipanggil pasti beda
    String? groupId = await _groupService.createGroup(
      _groupNameController.text.trim(),
      _currentUserId,
    );

    setState(() => _isLoading = false);

    if (groupId != null) {
      if (!mounted) return;
      // Kosongkan input nama grup supaya kalau mau bikin lagi, bersih
      _groupNameController.clear();
      
      _showSuccessDialog("Grup Berhasil Dibuat!", "Kode Grup kamu:\n\n$groupId\n\n(Kode ini hasil generate baru)");
      // Reload data
      await _loadMyGroup();
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal membuat grup.')),
      );
    }
  }

  void _handleJoinGroup() async {
    if (_groupIdController.text.isEmpty) return;
    setState(() => _isLoading = true);
    String groupIdInput = _groupIdController.text.trim().toUpperCase();

    bool success = await _groupService.joinGroup(groupIdInput, _currentUserId);
    setState(() => _isLoading = false);

    if (success) {
      if (!mounted) return;
      _groupIdController.clear(); // Kosongkan input
      _showSuccessDialog("Berhasil Join!", "Kamu sekarang sudah tergabung di grup $groupIdInput.");
      // Reload data
      await _loadMyGroup();
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal join. Cek kode grupnya.')),
      );
    }
  }

  void _handleSwitchGroup(String groupId) async {
    setState(() => _isLoading = true);
    bool success = await _groupService.switchGroup(_currentUserId, groupId);
    setState(() => _isLoading = false);

    if (success) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Berhasil switch ke grup $groupId')),
      );
      // Reload data
      await _loadMyGroup();
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal switch grup.')),
      );
    }
  }

  void _handleLeaveGroup(String groupId) async {
    setState(() => _isLoading = true);
    bool success = await _groupService.leaveGroup(groupId, _currentUserId);
    setState(() => _isLoading = false);

    if (success) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Berhasil keluar dari grup $groupId')),
      );
      // Reload data
      await _loadMyGroup();
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal keluar dari grup.')),
      );
    }
  }

  void _handleRemoveMember(String groupId, String memberId, String memberName) async {
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Konfirmasi'),
        content: Text('Apakah Anda yakin ingin mengeluarkan $memberName dari grup?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Ya')),
        ],
      ),
    ) ?? false;

    if (!confirm) return;

    setState(() => _isLoading = true);
    bool success = await _groupService.removeMember(groupId, _currentUserId, memberId);
    setState(() => _isLoading = false);

    if (success) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$memberName berhasil dikeluarkan dari grup')),
      );
      // Reload data
      await _loadMyGroup();
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal mengeluarkan anggota.')),
      );
    }
  }

  void _showMembersDialog(String groupId, String groupName, List<String> members, String adminId) async {
    bool isAdmin = adminId == _currentUserId;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Anggota Grup $groupName'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: members.length,
            itemBuilder: (context, index) {
              String memberId = members[index];
              return FutureBuilder<String>(
                future: _groupService.getUserName(memberId),
                builder: (context, snapshot) {
                  String name = snapshot.data ?? 'Loading...';
                  bool isCurrentUser = memberId == _currentUserId;
                  bool isGroupAdmin = memberId == adminId;
                  return ListTile(
                    title: Text(name),
                    subtitle: Text(isGroupAdmin ? 'Admin' : 'Anggota'),
                    trailing: isAdmin && !isCurrentUser && !isGroupAdmin
                        ? IconButton(
                            icon: const Icon(Icons.remove_circle, color: Colors.red),
                            onPressed: () => _handleRemoveMember(groupId, memberId, name),
                          )
                        : null,
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup')),
        ],
      ),
    );
  }

  void _showSuccessDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Tutup dialog
              // Kita tidak usah pop halaman groupScreen, biar user bisa lihat/copy lagi kalau mau
              // Atau kalau mau langsung balik ke map: Navigator.pop(context);
            },
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Menu Grup")),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text("Buat Grup Baru", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _groupNameController,
                    decoration: const InputDecoration(labelText: "Nama Grup", border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: _handleCreateGroup,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                    child: const Text("GENERATE KODE BARU"),
                  ),
                  const Divider(height: 50, thickness: 2),
                  const Text("Gabung Grup Teman", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _groupIdController,
                    decoration: const InputDecoration(labelText: "Masukkan Kode Grup", border: OutlineInputBorder()),
                    textCapitalization: TextCapitalization.characters,
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: _handleJoinGroup,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                    child: const Text("GABUNG GRUP"),
                  ),
                  const Divider(height: 50, thickness: 2),
                  const Text("Grup tersedia", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  if (_joinedGroups.isEmpty)
                    const Text("Kamu belum tergabung di grup manapun.")
                  else
                    ListView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      shrinkWrap: true,
                      itemCount: _joinedGroups.length,
                      itemBuilder: (context, index) {
                        String groupId = _joinedGroups[index];
                        bool isActive = groupId == _myGroupId;
                        return FutureBuilder<DocumentSnapshot>(
                          future: _locationService.streamGroupData(groupId).first,
                          builder: (context, snapshot) {
                            if (!snapshot.hasData || !snapshot.data!.exists) {
                              return ListTile(
                                title: Text('Grup $groupId'),
                                subtitle: const Text('Data tidak ditemukan'),
                              );
                            }
                            Map<String, dynamic> data = snapshot.data!.data() as Map<String, dynamic>;
                            String name = data['name'] ?? 'Tanpa Nama';
                            String adminId = data['adminId'] ?? '';
                            List<String> members = List<String>.from(data['members'] ?? []);
                            return ListTile(
                              title: Text(name),
                              subtitle: Text('ID: $groupId${isActive ? ' (Aktif)' : ''}'),
                              trailing: isActive
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        ElevatedButton(
                                          onPressed: () => _showMembersDialog(groupId, name, members, adminId),
                                          child: const Text('Anggota'),
                                        ),
                                        const SizedBox(width: 8),
                                        ElevatedButton(
                                          onPressed: () => _handleLeaveGroup(groupId),
                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                                          child: const Text('Keluar'),
                                        ),
                                      ],
                                    )
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        ElevatedButton(
                                          onPressed: () => _handleSwitchGroup(groupId),
                                          child: const Text('Buka'),
                                        ),
                                        const SizedBox(width: 8),
                                        ElevatedButton(
                                          onPressed: () => _handleLeaveGroup(groupId),
                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                                          child: const Text('Keluar'),
                                        ),
                                      ],
                                    ),
                            );
                          },
                        );
                      },
                    ),
                ],
              ),
            ),
    );
  }
}