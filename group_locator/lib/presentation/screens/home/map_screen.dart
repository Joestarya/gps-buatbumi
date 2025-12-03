import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart'; // Peta
import 'package:latlong2/latlong.dart'; // Koordinat
import 'package:geolocator/geolocator.dart'; // GPS
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../data/services/auth_service.dart';
import '../../../data/services/location_service.dart';
import '../auth/login_screen.dart';
import '../group/group_screen.dart';
import '../../../data/tomtom_routing_service.dart';
import '../../../config/tomtom_config.dart';
import '../../../data/osm_search_service.dart';
import '../../../data/meeting_repository.dart';
import 'place_search_osm_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  final AuthService _authService = AuthService();
  final LocationService _locationService = LocationService();
  final String _myUid = FirebaseAuth.instance.currentUser!.uid;
  
  // KONTROLER PETA (Untuk Fitur Kompas & Recenter)
  final MapController _mapController = MapController();
  // PENCARIAN TEMPAT (TomTom Search)
  final TextEditingController _searchController = TextEditingController();
  final OsmSearchService _searchService = OsmSearchService();
  final MeetingRepository _meetingRepo = MeetingRepository();
  List<OsmPlace> _searchResults = [];
  bool _searchLoading = false;
  bool _searchOpen = false;

  LatLng? _myPosition;
  String? _myGroupId;
  bool _isLoading = true;
  bool _isMemberListOpen = false;
  StreamSubscription<Position>? _positionStream;
  String? _selectedUserId; // ID anggota yang dipilih dari legenda
  static const Distance _distanceCalc = Distance();
  final TomTomRoutingService _routingService = TomTomRoutingService();
  List<LatLng> _routePoints = [];
  String? _routeInfo; // e.g. "1.2 km • 5 min"
  bool _loadingRoute = false;

  String _formatDistance(double meters) {
    if (meters < 1) return "<1 m";
    if (meters < 1000) return "${meters.round()} m";
    double km = meters / 1000;
    return km < 10 ? "${km.toStringAsFixed(2)} km" : "${km.toStringAsFixed(1)} km";
  }

  @override
  void initState() {
    super.initState();
    _initMapData();
  }

  Future<void> _navigateTo(LatLng target) async {
    if (_myPosition == null) return;
    setState(() {
      _loadingRoute = true;
      _routePoints = [];
      _routeInfo = null;
    });
    final result = await _routingService.fetchRoute(_myPosition!, target);
    if (!mounted) return;
    setState(() {
      _loadingRoute = false;
      if (result != null && result.points.isNotEmpty) {
        _routePoints = result.points;
        final km = result.lengthMeters / 1000.0;
        final minutes = (result.travelTimeSeconds / 60).round();
        _routeInfo = '${km.toStringAsFixed(km < 10 ? 2 : 1)} km • ${minutes} min';
        // Center map roughly between start & destination
        final midIndex = result.points.length ~/ 2;
        _mapController.move(result.points[midIndex], 14.5);
      } else {
        _routeInfo = 'Rute tidak ditemukan';
      }
    });
  }

  void _clearRoute() {
    setState(() {
      _routePoints = [];
      _routeInfo = null;
    });
  }

  void _initMapData() async {
    // 1. Cari & Upload Lokasi Awal (Force Update biar Laptop bisa lihat HP)
    await _checkPermissionsAndLocate();
    
    // 2. Cari Saya ada di Grup mana
    String? groupId = await _locationService.findMyGroupId(_myUid);
    setState(() {
      _myGroupId = groupId;
    });

    // 3. Mulai pantau pergerakan realtime
    _listenToMyMovement();
  }

  Future<void> _checkPermissionsAndLocate() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    // Ambil lokasi saat ini
    Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);

    if (!mounted) return;

    setState(() {
      _myPosition = LatLng(position.latitude, position.longitude);
      _isLoading = false;
    });
    
    // PENTING: Langsung upload ke Firebase saat pertama kali buka!
    // Ini solusi supaya user di Laptop bisa langsung lihat user HP yang diam.
    _locationService.updateUserLocation(
        _myUid, position.latitude, position.longitude);
        
    // Pindahkan kamera peta ke lokasi kita
    _mapController.move(_myPosition!, 15.0);
  }

  void _listenToMyMovement() {
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    );

    // Perhatikan: Kita hapus "if (position != null)"
    _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings)
        .listen((Position position) {
            
      // Langsung eksekusi saja
      setState(() {
        _myPosition = LatLng(position.latitude, position.longitude);
      });
      
      _locationService.updateUserLocation(
          _myUid, position.latitude, position.longitude);
    });
  }

  Future<void> _performSearch() async {
    final q = _searchController.text.trim();
    if (q.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _searchLoading = true);
    try {
      final res = await _searchService.search(q, limit: 10);
      setState(() => _searchResults = res);
    } finally {
      if (mounted) setState(() => _searchLoading = false);
    }
  }

  void _openInviteSheetForPlace(String groupId, OsmPlace place) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final Set<String> _selectedInvitees = {};
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
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
                      _selectedInvitees.clear();
                      for (final d in docs) {
                        final data = d.data() as Map<String, dynamic>;
                        final uid = (data['uid'] ?? '').toString();
                        if (uid.isNotEmpty && uid != user.uid) {
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
                          final isMe = uid == user.uid;
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
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.send),
                      label: const Text('Kirim Undangan'),
                      onPressed: () async {
                        final meetingId = await _meetingRepo.createMeeting(
                          groupId: groupId,
                          createdBy: user.uid,
                          placeName: place.name,
                          lat: place.lat,
                          lon: place.lon,
                          address: place.displayAddress,
                        );
                        await _meetingRepo.addInvites(meetingId, _selectedInvitees.toList());
                        if (!mounted) return;
                        Navigator.of(ctx).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Undangan terkirim.')),
                        );
                      },
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

  void _handleLogout() async {
    await _authService.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context, MaterialPageRoute(builder: (context) => const LoginScreen()), (route) => false);
  }

  // FITUR 3: KOMPAS (Reset Rotasi ke Utara)
  void _resetNorth() {
    // Rotasi 0 derajat artinya Utara di atas
    _mapController.rotate(0);
  }

  // FITUR 4: RECENTER (Kembali ke Posisi Saya)
  void _recenterPosition() {
    if (_myPosition != null) {
      _mapController.move(_myPosition!, 15.0);
    }
  }

  // Dialog konfirmasi logout
  void _showLogoutConfirmation(BuildContext context) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text('Konfirmasi Logout'),
        content: const Text('Apakah kamu yakin ingin logout?'),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // Close
            },
            child: const Text('Batalkan'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // Close
              _handleLogout(); // Logging out
            },
            child: const Text('Logout'),
          ),
        ],
      );
    },
  );
}

  @override
  void dispose() {
    _positionStream?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_myGroupId == null ? "Belum Ada Grup" : "Grup: $_myGroupId"),
        actions: [
          IconButton(
          icon: const Icon(Icons.logout),
          tooltip: 'Logout',
          onPressed: () => _showLogoutConfirmation(context), 
  ),
],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                FlutterMap(
                  mapController: _mapController, // Pasang Controller disini
                  options: MapOptions(
                    initialCenter: _myPosition!,
                    initialZoom: 15.0,
                    // Biarkan user memutar peta (rotate) pakai 2 jari
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all, 
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://api.tomtom.com/map/1/tile/basic/main/{z}/{x}/{y}.png?key={apiKey}',
                      additionalOptions: {
                        'apiKey': TomTomConfig.apiKey,
                      },
                      userAgentPackageName: 'com.example.group_locator',
                    ),
                    if (_routePoints.isNotEmpty)
                      PolylineLayer(
                        polylines: [
                          Polyline(points: _routePoints, strokeWidth: 5, color: Colors.deepPurpleAccent),
                        ],
                      ),
                    // MARKER SAYA
                    MarkerLayer(markers: [
                        if (_myPosition != null)
                          Marker(
                            point: _myPosition!,
                            width: 80, height: 80,
                            child: const Column(children: [
                                Icon(Icons.navigation, color: Colors.red, size: 40), // Ganti icon panah biar keren
                                Text("Saya", style: TextStyle(fontWeight: FontWeight.bold)),
                            ]),
                          ),
                    ]),
                    // MARKER TEMAN (STREAM)
                    if (_myGroupId != null)
                      StreamBuilder<DocumentSnapshot>(
                        stream: _locationService.streamGroupData(_myGroupId!),
                        builder: (context, groupSnapshot) {
                          if (!groupSnapshot.hasData || !groupSnapshot.data!.exists) return const SizedBox();
                          Map<String, dynamic> groupData = groupSnapshot.data!.data() as Map<String, dynamic>;
                          List<dynamic> memberIds = groupData['members'] ?? [];

                          return StreamBuilder<QuerySnapshot>(
                            stream: _locationService.streamUsersLocation(List<String>.from(memberIds)),
                            builder: (context, userSnapshot) {
                              if (!userSnapshot.hasData) return const SizedBox();
                              List<Marker> friendMarkers = [];
                              for (var doc in userSnapshot.data!.docs) {
                                var data = doc.data() as Map<String, dynamic>;
                                if (data['uid'] != _myUid && data['latitude'] != null) {
                                  final bool isSelected = data['uid'] == _selectedUserId;
                                  friendMarkers.add(Marker(
                                      point: LatLng(data['latitude'], data['longitude']),
                                      width: isSelected ? 120 : 100,
                                      height: isSelected ? 100 : 80,
                                      child: Column(children: [
                                          AnimatedContainer(
                                            duration: const Duration(milliseconds: 250),
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: isSelected ? Colors.deepPurple : Colors.blue,
                                              boxShadow: isSelected
                                                  ? [
                                                      BoxShadow(
                                                        color: Colors.deepPurple.withOpacity(0.5),
                                                        blurRadius: 12,
                                                        spreadRadius: 4,
                                                      )
                                                    ]
                                                  : [],
                                            ),
                                            child: Icon(
                                              Icons.face,
                                              color: Colors.white,
                                              size: isSelected ? 46 : 40,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: isSelected ? Colors.deepPurple.shade50 : Colors.white,
                                              borderRadius: BorderRadius.circular(6),
                                              border: isSelected ? Border.all(color: Colors.deepPurple, width: 1) : null,
                                            ),
                                            child: Text(
                                              data['name'] ?? "Teman",
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: isSelected ? Colors.deepPurple : Colors.black,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                      ]),
                                  ));
                                }
                              }
                              return MarkerLayer(markers: friendMarkers);
                            },
                          );
                        },
                      ),
                  ],
                ),
                // Inline Search Bar (Top overlay)
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Material(
                        elevation: 2,
                        borderRadius: BorderRadius.circular(12),
                        child: TextField(
                          controller: _searchController,
                          onTap: () => setState(() => _searchOpen = true),
                          onSubmitted: (_) => _performSearch(),
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            hintText: 'Cari tempat (TomTom)',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                            filled: true,
                            fillColor: Colors.white,
                            suffixIcon: IconButton(
                              icon: _searchLoading
                                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.search),
                              onPressed: _searchLoading ? null : _performSearch,
                            ),
                          ),
                        ),
                      ),
                      if (_searchOpen && _searchResults.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          constraints: const BoxConstraints(maxHeight: 260),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
                          ),
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            shrinkWrap: true,
                            itemCount: _searchResults.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final p = _searchResults[i];
                              return ListTile(
                                dense: true,
                                title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Text(p.displayAddress ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                                onTap: () {
                                  setState(() {
                                    _searchOpen = false;
                                    _searchResults = [];
                                  });
                                  // Pindahkan kamera ke lokasi pilihan
                                  _mapController.move(LatLng(p.lat, p.lon), 16.0);
                                  if (_myGroupId != null) {
                                    _openInviteSheetForPlace(_myGroupId!, p);
                                  }
                                },
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                
// --- PANEL ANGGOTA (Versi Bisa Buka/Tutup) ---
                if (_myGroupId != null)
                  Positioned(
                    right: 12,
                    top: 170, // Turunkan ke 170 biar GAK NABRAK tombol kompas
                    child: StreamBuilder<DocumentSnapshot>(
                      stream: _locationService.streamGroupData(_myGroupId!),
                      builder: (context, groupSnapshot) {
                        if (!groupSnapshot.hasData || !groupSnapshot.data!.exists) {
                          return const SizedBox();
                        }
                        
                        final Map<String, dynamic> groupData = groupSnapshot.data!.data() as Map<String, dynamic>;
                        final List<dynamic> memberIdsDyn = groupData['members'] ?? [];
                        final List<String> memberIds = memberIdsDyn.map((e) => e.toString()).toList();

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.end, // Rata kanan
                          children: [
                            // 1. TOMBOL HEADER (Selalu Muncul)
                            InkWell(
                              onTap: () {
                                setState(() {
                                  _isMemberListOpen = !_isMemberListOpen; // Ubah status Buka/Tutup
                                });
                              },
                              child: Container(
                                height: 45,
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(25), // Bulat lonjong
                                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min, // Lebar menyesuaikan isi
                                  children: [
                                    const Icon(Icons.people, color: Colors.blue),
                                    const SizedBox(width: 8),
                                    Text(
                                      "Anggota (${memberIds.length})", 
                                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)
                                    ),
                                    const SizedBox(width: 8),
                                    // Panah indikator (Atas/Bawah)
                                    Icon(
                                      _isMemberListOpen ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                      color: Colors.grey,
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(height: 8), // Jarak antara tombol dan list

                            // 2. DAFTAR MEMBER (Cuma Muncul Kalau _isMemberListOpen == true)
                            if (_isMemberListOpen)
                              Container(
                                width: 200,
                                constraints: const BoxConstraints(maxHeight: 250), // Batasi tinggi
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.95),
                                  borderRadius: BorderRadius.circular(18),
                                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
                                ),
                                child: memberIds.isEmpty
                                    ? const Padding(padding: EdgeInsets.all(12), child: Text("Sepi banget..."))
                                    : StreamBuilder<QuerySnapshot>(
                                        stream: _locationService.streamUsersLocation(memberIds),
                                        builder: (context, usersSnapshot) {
                                          if (!usersSnapshot.hasData) return const Padding(padding: EdgeInsets.all(10), child: Center(child: CircularProgressIndicator()));
                                          
                                          final docs = usersSnapshot.data!.docs;
                                          return ListView.separated(
                                            padding: const EdgeInsets.all(12),
                                            shrinkWrap: true,
                                            itemCount: docs.length,
                                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                                            itemBuilder: (context, index) {
                                              final data = docs[index].data() as Map<String, dynamic>;
                                              final String name = (data['name'] ?? 'No Name').toString();
                                              final bool isMe = data['uid']?.toString() == _myUid;
                                              
                                              return InkWell(
                                                onTap: () {
                                                  if (data['latitude'] != null) {
                                                    _mapController.move(LatLng(data['latitude'], data['longitude']), 16.0);
                                                    setState(() => _selectedUserId = data['uid']);
                                                  }
                                                },
                                                child: Row(
                                                  children: [
                                                    // Avatar Kecil
                                                    Container(
                                                      width: 32, height: 32,
                                                      decoration: BoxDecoration(
                                                        color: isMe ? Colors.blue.shade100 : Colors.grey.shade200,
                                                        shape: BoxShape.circle,
                                                        border: data['uid'] == _selectedUserId ? Border.all(color: Colors.blue, width: 2) : null,
                                                      ),
                                                      child: Center(
                                                        child: Text(name.isNotEmpty ? name[0].toUpperCase() : "?", 
                                                          style: TextStyle(fontWeight: FontWeight.bold, color: isMe ? Colors.blue : Colors.black54)),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    // Nama & Status
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Text(isMe ? "$name (Saya)" : name, 
                                                            style: TextStyle(fontSize: 12, fontWeight: isMe ? FontWeight.bold : FontWeight.normal),
                                                            overflow: TextOverflow.ellipsis),
                                                          if (_myPosition != null && data['latitude'] != null)
                                                            Text(
                                                              _formatDistance(_distanceCalc(_myPosition!, LatLng(data['latitude'], data['longitude']))),
                                                              style: const TextStyle(fontSize: 10, color: Colors.grey),
                                                            ),
                                                        ],
                                                      ),
                                                    ),
                                                    // Tombol Navigasi
                                                    if (!isMe && data['latitude'] != null) 
                                                      IconButton(
                                                        icon: const Icon(Icons.navigation, size: 18, color: Colors.blue),
                                                        padding: EdgeInsets.zero,
                                                        constraints: const BoxConstraints(),
                                                        onPressed: () async {
                                                          final double lat = (data['latitude'] as num).toDouble();
                                                          final double lng = (data['longitude'] as num).toDouble();
                                                          await _navigateTo(LatLng(lat, lng));
                                                        },
                                                      ),
                                                  ],
                                                ),
                                              );
                                            },
                                          );
                                        },
                                      ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),

                // --- TOMBOL FITUR BARU (DI POJOK KANAN ATAS) ---
                Positioned(
                  top: 20,
                  right: 20,
                  child: Column(
                    children: [
                      // Tombol Pencarian Tempat OSM
                      FloatingActionButton.small(
                        heroTag: "btnSearchOSM",
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PlaceSearchOsmScreen(),
                            ),
                          );
                        },
                        backgroundColor: Colors.white,
                        child: const Icon(Icons.search, color: Colors.blue),
                      ),
                      const SizedBox(height: 10),
                      // Tombol Kompas
                      FloatingActionButton.small(
                        heroTag: "btnCompass",
                        onPressed: _resetNorth,
                        backgroundColor: Colors.white,
                        child: const Icon(Icons.explore, color: Colors.blue),
                      ),
                      const SizedBox(height: 10),
                      // Tombol Recenter
                      FloatingActionButton.small(
                        heroTag: "btnRecenter",
                        onPressed: _recenterPosition,
                        backgroundColor: Colors.white,
                        child: const Icon(Icons.my_location, color: Colors.blue),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
                if (_loadingRoute)
                  const Positioned(
                    top: 12,
                    left: 12,
                    child: Card(
                      elevation: 4,
                      child: Padding(
                        padding: EdgeInsets.all(10),
                        child: Row(
                          children: [
                            SizedBox(height:16,width:16,child:CircularProgressIndicator(strokeWidth:2)),
                            SizedBox(width:8),
                            Text('Mengambil rute...'),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (_routeInfo != null && !_loadingRoute)
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Card(
                      elevation: 4,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.directions, color: Colors.deepPurpleAccent),
                            const SizedBox(width: 8),
                            Text(_routeInfo!, style: const TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(width: 12),
                            InkWell(
                              onTap: _clearRoute,
                              child: const Icon(Icons.close, size: 18),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (context) => const GroupScreen()))
              .then((_) => _initMapData());
        },
        label: const Text("Menu Grup"),
        icon: const Icon(Icons.group),
      ),
    );
  }
}