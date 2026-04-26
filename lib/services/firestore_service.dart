import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/message.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Collection reference
  CollectionReference _getUserChatCollection(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('chats');
  }

  /// Save a single message to Firestore
  Future<void> saveMessage(String userId, Message message) async {
    try {
      await _getUserChatCollection(userId).doc(message.id).set(message.toJson());
    } catch (e) {
      print('Error saving message to Firestore: $e');
    }
  }

  /// Load all messages for a user, sorted by timestamp
  Future<List<Message>> loadMessages(String userId) async {
    try {
      final snapshot = await _getUserChatCollection(userId)
          .orderBy('timestamp', descending: false)
          .get();
      
      return snapshot.docs
          .map((doc) => Message.fromJson(doc.data() as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('Error loading messages from Firestore: $e');
      return [];
    }
  }

  /// Clear all messages for a user
  Future<void> clearMessages(String userId) async {
    try {
      final snapshot = await _getUserChatCollection(userId).get();
      final batch = _firestore.batch();
      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (e) {
      print('Error clearing messages from Firestore: $e');
    }
  }

  /// Delete all messages for a specific session
  Future<void> deleteSession(String userId, String sessionId) async {
    try {
      final snapshot = await _getUserChatCollection(userId)
          .where('sessionId', isEqualTo: sessionId)
          .get();
      
      final batch = _firestore.batch();
      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (e) {
      print('Error deleting session from Firestore: $e');
    }
  }
}
