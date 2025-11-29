import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../data/services/group_service.dart';

class GroupScreen extends StatefulWidget {
  const GroupScreen({super.key});

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> {
  final TextEditingController _groupNameController = TextEditingController();
  final TextEditingController _groupIdController = TextEditingController();
  final GroupService _groupService = GroupService();
  final String _currentUserId = FirebaseAuth.instance.currentUser!.uid;
  bool _isLoading = false;

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
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal join. Cek kode grupnya.')),
      );
    }
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
                ],
              ),
            ),
    );
  }
}