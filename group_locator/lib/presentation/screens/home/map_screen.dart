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
                                  friendMarkers.add(Marker(
                                      point: LatLng(data['latitude'], data['longitude']),
                                      width: 100, height: 80,
                                      child: Column(children: [
                                          const Icon(Icons.face, color: Colors.blue, size: 40),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(5)),
                                            child: Text(data['name'] ?? "Teman", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
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