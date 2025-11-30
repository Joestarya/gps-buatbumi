import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart'; // Peta
import 'package:latlong2/latlong.dart'; // Koordinat
import 'package:geolocator/geolocator.dart'; // GPS
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/services/auth_service.dart';
import '../../../data/services/location_service.dart';
import '../auth/login_screen.dart';
import '../group/group_screen.dart';

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

  LatLng? _myPosition;
  String? _myGroupId;
  bool _isLoading = true;
  StreamSubscription<Position>? _positionStream;
  String? _selectedUserId; // ID anggota yang dipilih dari legenda
  static const Distance _distanceCalc = Distance();

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
        actions: [IconButton(icon: const Icon(Icons.logout), onPressed: _handleLogout)],
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
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.group_locator',
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
                
// --- PANEL ANGGOTA (Versi Final: Layout Aman + Ada Navigasi) ---
                if (_myGroupId != null)
                  Positioned(
                    right: 12,
                    top: 100,
                    child: Container(
                      width: 200, // Lebar kotak
                      // 1. Batasi tinggi maksimal biar aman di Laptop
                      constraints: const BoxConstraints(
                        maxHeight: 300, 
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.95),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
                      ),
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
                            mainAxisSize: MainAxisSize.min, // Biar tinggi menyesuaikan isi
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // HEADER
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                child: Row(
                                  children: [
                                    const Icon(Icons.group, size: 18, color: Colors.black54),
                                    const SizedBox(width: 8),
                                    const Text("Anggota", style: TextStyle(fontWeight: FontWeight.w600)),
                                    const Spacer(),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(10)),
                                      child: Text(memberIds.length.toString(), style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                                    )
                                  ],
                                ),
                              ),
                              const Divider(height: 1),
                              
                              // LIST MEMBER (Scrollable)
                              Flexible(
                                child: memberIds.isEmpty
                                    ? const Padding(padding: EdgeInsets.all(12), child: Text("Sepi banget...", style: TextStyle(fontSize: 12)))
                                    : StreamBuilder<QuerySnapshot>(
                                        stream: _locationService.streamUsersLocation(memberIds),
                                        builder: (context, usersSnapshot) {
                                          if (!usersSnapshot.hasData) return const Center(child: LinearProgressIndicator());
                                          
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
                                                  // Klik nama -> Pindah kamera
                                                  if (data['latitude'] != null) {
                                                    _mapController.move(LatLng(data['latitude'], data['longitude']), 16.0);
                                                    setState(() => _selectedUserId = data['uid']);
                                                  }
                                                },
                                                child: Row(
                                                  children: [
                                                    // 1. Avatar
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
                                                    
                                                    // 2. Nama & Jarak
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

                                                    // 3. TOMBOL NAVIGASI (INI YANG TADI HILANG)
                                                    if (!isMe && data['latitude'] != null) 
                                                      IconButton(
                                                        icon: const Icon(Icons.navigation, size: 18, color: Colors.blue),
                                                        padding: EdgeInsets.zero,
                                                        constraints: const BoxConstraints(), // Biar tombolnya gak makan tempat
                                                        onPressed: () async {
                                                          // Buka Google Maps
                                                          final double lat = (data['latitude'] as num).toDouble();
                                                          final double lng = (data['longitude'] as num).toDouble();
                                                          
                                                          // URL Google Maps Direction
                                                          final Uri url = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
                                                          
                                                          if (await canLaunchUrl(url)) {
                                                            await launchUrl(url, mode: LaunchMode.externalApplication);
                                                          } else {
                                                            ScaffoldMessenger.of(context).showSnackBar(
                                                              const SnackBar(content: Text('Tidak bisa membuka Google Maps')),
                                                            );
                                                          }
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
                  ),

                // --- TOMBOL FITUR BARU (DI POJOK KANAN ATAS) ---
                Positioned(
                  top: 20,
                  right: 20,
                  child: Column(
                    children: [
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
                    ],
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