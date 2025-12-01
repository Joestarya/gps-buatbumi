import 'package:cloud_firestore/cloud_firestore.dart';

class MeetingRepository {
  final _db = FirebaseFirestore.instance;

  Future<String> createMeeting({
    required String groupId,
    required String createdBy,
    required String placeName,
    required double lat,
    required double lon,
    String? address,
    DateTime? when,
  }) async {
    final doc = await _db.collection('meetings').add({
      'groupId': groupId,
      'createdBy': createdBy,
      'placeName': placeName,
      'lat': lat,
      'lon': lon,
      'address': address,
      'when': when,
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'planned',
    });
    return doc.id;
  }

  Future<void> addInvites(String meetingId, List<String> userIds) async {
    final batch = _db.batch();
    final meetingRef = _db.collection('meetings').doc(meetingId);
    for (final uid in userIds) {
      final ref = meetingRef.collection('invites').doc(uid);
      batch.set(ref, {
        'uid': uid,
        'status': 'pending',
        'sentAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }
}
