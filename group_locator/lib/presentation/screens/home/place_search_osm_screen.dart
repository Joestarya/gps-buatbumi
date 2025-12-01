import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../data/services/group_service.dart';
import '../../../data/services/location_service.dart';

class OsmPlaceResult {
  final String displayName;
  final double lat;
  final double lon;
  OsmPlaceResult({required this.displayName, required this.lat, required this.lon});
}

class PlaceSearchOsmScreen extends StatefulWidget {
  const PlaceSearchOsmScreen({super.key});

  @override
  State<PlaceSearchOsmScreen> createState() => _PlaceSearchOsmScreenState();
}

class _PlaceSearchOsmScreenState extends State<PlaceSearchOsmScreen> {
  final TextEditingController _queryController = TextEditingController();
  final GroupService _groupService = GroupService();
  final LocationService _locationService = LocationService();
  final String _currentUserId = FirebaseAuth.instance.currentUser!.uid;
  List<OsmPlaceResult> _results = [];
  bool _isSearching = false;
  String? _myGroupId;
  List<String> _groupMembers = [];
  OsmPlaceResult? _selectedPlace;
  final List<String> _selectedInvitees = [];

  @override
  void initState() {
    super.initState();
    _loadGroupData();
  }

  Future<void> _loadGroupData() async {
    _myGroupId = await _locationService.findMyGroupId(_currentUserId);
    if (_myGroupId != null) {
      _groupMembers = await _groupService.getGroupMembers(_myGroupId!);
      _groupMembers.remove(_currentUserId);
    }
    setState(() {});
  }

  Future<void> _searchPlaces() async {
    final q = _queryController.text.trim();
    if (q.isEmpty) return;
    setState(() { _isSearching = true; _results = []; _selectedPlace = null; });
    final uri = Uri.parse('https://nominatim.openstreetmap.org/search?format=json&q=${Uri.encodeComponent(q)}&limit=10&countrycodes=id');
    final resp = await http.get(uri, headers: { 'User-Agent': 'group-locator-app/1.0' });
    if (resp.statusCode == 200) {
      final List data = json.decode(resp.body);
      _results = data.map((e) {
        return OsmPlaceResult(
          displayName: e['display_name'] ?? 'Unknown',
          lat: double.tryParse(e['lat'] ?? '0') ?? 0,
          lon: double.tryParse(e['lon'] ?? '0') ?? 0,
        );
      }).toList();
    }
    setState(() { _isSearching = false; });
  }

  void _selectPlace(OsmPlaceResult place) {
    setState(() { _selectedPlace = place; });
  }

  void _toggleInvitee(String uid) {
    setState(() {
      if (_selectedInvitees.contains(uid)) {
        _selectedInvitees.remove(uid);
      } else {
        _selectedInvitees.add(uid);
      }
    });
  }

  Future<void> _sendInvites() async {
    if (_selectedPlace == null || _selectedInvitees.isEmpty) return;
    await FirebaseFirestore.instance.collection('invites').add({
      'inviter': _currentUserId,
      'invitees': _selectedInvitees,
      'place': {
        'name': _selectedPlace!.displayName,
        'lat': _selectedPlace!.lat,
        'lon': _selectedPlace!.lon,
        'source': 'osm',
      },
      'timestamp': FieldValue.serverTimestamp(),
      'groupId': _myGroupId,
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Undangan dikirim')));
    Navigator.pop(context);
  }

  Future<void> _openInGoogleMaps() async {
    if (_selectedPlace == null) return;
    final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=${_selectedPlace!.lat},${_selectedPlace!.lon}');
    // Pengalihan ke Google Maps akan dilakukan di map_screen menggunakan url_launcher bila diperlukan.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cari Tempat (OSM)')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _queryController,
                    decoration: const InputDecoration(
                      hintText: 'Cari lokasi (mis: Monas, Bandung...)',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _searchPlaces(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: _searchPlaces, child: const Text('Cari')),
              ],
            ),
          ),
          if (_isSearching) const LinearProgressIndicator(),
          if (_results.isNotEmpty)
            Expanded(
              child: ListView.builder(
                itemCount: _results.length,
                itemBuilder: (context, i) {
                  final r = _results[i];
                  final selected = _selectedPlace == r;
                  return ListTile(
                    title: Text(r.displayName, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${r.lat.toStringAsFixed(5)}, ${r.lon.toStringAsFixed(5)}'),
                    selected: selected,
                    onTap: () => _selectPlace(r),
                  );
                },
              ),
            )
          else if (!_isSearching)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('Masukkan kata kunci untuk mencari lokasi.'),
            ),
          if (_selectedPlace != null)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4),
                    child: Text('Tempat dipilih:', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: Text(_selectedPlace!.displayName),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: Text('Undang anggota grup:'),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _groupMembers.length,
                      itemBuilder: (context, i) {
                        final uid = _groupMembers[i];
                        final checked = _selectedInvitees.contains(uid);
                        return CheckboxListTile(
                          value: checked,
                          onChanged: (_) => _toggleInvitee(uid),
                          title: Text('User $uid'),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      children: [
                        ElevatedButton(
                          onPressed: _sendInvites,
                          child: const Text('Kirim Undangan'),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton(
                          onPressed: _openInGoogleMaps,
                          child: const Text('Lihat di Google Maps'),
                        ),
                      ],
                    ),
                  )
                ],
              ),
            ),
        ],
      ),
    );
  }
}
