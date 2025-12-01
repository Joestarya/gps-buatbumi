import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/osm_search_service.dart';
import '../../data/meeting_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PlaceSearchPage extends StatefulWidget {
  final String? groupId;
  const PlaceSearchPage({super.key, this.groupId});

  @override
  State<PlaceSearchPage> createState() => _PlaceSearchPageState();
}

class _PlaceSearchPageState extends State<PlaceSearchPage> {
  final _controller = TextEditingController();
  final _service = OsmSearchService();
  final _meetings = MeetingRepository();
  List<OsmPlace> _results = [];
  bool _loading = false;
  final Set<String> _selectedInvitees = {};

  Future<void> _search() async {
    setState(() => _loading = true);
    try {
      final res = await _service.search(_controller.text, limit: 15);
      setState(() => _results = res);
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _sharePlace(OsmPlace place) async {
    String? meetingId;
    final user = FirebaseAuth.instance.currentUser;
    if (widget.groupId != null && user != null) {
      // Save meeting to Firestore for the group
      meetingId = await _meetings.createMeeting(
        groupId: widget.groupId!,
        createdBy: user.uid,
        placeName: place.name,
        lat: place.lat,
        lon: place.lon,
        address: place.displayAddress,
      );
    }
    final meetingLink = meetingId != null
        ? 'group_locator://meet?id=$meetingId'
        : 'https://www.openstreetmap.org/?mlat=${place.lat}&mlon=${place.lon}#map=17/${place.lat}/${place.lon}';
    final text = 'Tempat ketemuan: ${place.name}\nLokasi: $meetingLink';
    final uri = Uri.parse('sms:?body=${Uri.encodeComponent(text)}');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      // Fallback generic share via mailto to open chooser on web/desktop
      final mail = Uri.parse('mailto:?subject=${Uri.encodeComponent('Invite Ketemuan')}&body=${Uri.encodeComponent(text)}');
      await launchUrl(mail, mode: LaunchMode.externalApplication);
    }
  }

  void _openInviteSheet(OsmPlace place) {
    if (widget.groupId == null) {
      _sharePlace(place);
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        _selectedInvitees.clear();
        final groupId = widget.groupId!;
        final user = FirebaseAuth.instance.currentUser;
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  title: Text('Undang Teman ke: ${place.name}'),
                  subtitle: const Text('Pilih anggota grup untuk diundang'),
                ),
                const Divider(height: 1),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .where('currentGroupId', isEqualTo: groupId)
                        .snapshots(),
                    builder: (ctx, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final docs = snapshot.data!.docs;
                      if (docs.isEmpty) {
                        return const Center(child: Text('Belum ada anggota di grup ini.'));
                      }
                      // Preselect everyone except self
                      _selectedInvitees.clear();
                      for (final d in docs) {
                        final data = d.data() as Map<String, dynamic>;
                        final uid = (data['uid'] ?? '').toString();
                        if (uid.isNotEmpty && uid != user?.uid) {
                          _selectedInvitees.add(uid);
                        }
                      }
                      return ListView.separated(
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final data = docs[i].data() as Map<String, dynamic>;
                          final uid = (data['uid'] ?? '').toString();
                          final name = (data['name'] ?? 'Teman').toString();
                          final isMe = uid == user?.uid;
                          final checked = _selectedInvitees.contains(uid);
                          return CheckboxListTile(
                            value: isMe ? false : checked,
                            onChanged: isMe
                                ? null
                                : (v) {
                                    setState(() {
                                      if (v == true) {
                                        _selectedInvitees.add(uid);
                                      } else {
                                        _selectedInvitees.remove(uid);
                                      }
                                    });
                                  },
                            title: Text(isMe ? '$name (Saya)' : name),
                          );
                        },
                      );
                    },
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.send),
                            label: const Text('Kirim Undangan'),
                            onPressed: () async {
                              final user = FirebaseAuth.instance.currentUser;
                              if (user == null) return;
                              // Buat meeting dan kirim undangan
                              final id = await _meetings.createMeeting(
                                groupId: groupId,
                                createdBy: user.uid,
                                placeName: place.name,
                                lat: place.lat,
                                lon: place.lon,
                                address: place.displayAddress,
                              );
                              await _meetings.addInvites(id, _selectedInvitees.toList());
                              if (mounted) {
                                Navigator.of(ctx).pop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Undangan terkirim ke anggota terpilih.')),
                                );
                              }
                              // Opsional: buka share intent juga
                              await _sharePlace(place);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cari Tempat (OSM)'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: 'Cari tempat, misal: cafe bandung',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _loading ? null : _search,
                  child: _loading
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Search'),
                )
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: _results.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final place = _results[index];
                return ListTile(
                  title: Text(place.name),
                  subtitle: Text(place.displayAddress ?? ''),
                  trailing: IconButton(
                    icon: const Icon(Icons.share),
                    onPressed: () => _openInviteSheet(place),
                    tooltip: 'Invite teman ke tempat ini',
                  ),
                  onTap: () => _openInviteSheet(place),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
