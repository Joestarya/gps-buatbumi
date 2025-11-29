import 'package:cloud_firestore/cloud_firestore.dart';

class FirebaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  FirebaseService();

  // Example placeholder: fetch a collection
  Future<QuerySnapshot> fetchCollection(String path) async {
    return _db.collection(path).get();
  }
}
