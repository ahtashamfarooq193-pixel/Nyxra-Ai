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

  /// Delete a single message from Firestore
  Future<void> deleteMessage(String userId, String messageId) async {
    try {
      await _getUserChatCollection(userId).doc(messageId).delete();
    } catch (e) {
      print('Error deleting message from Firestore: $e');
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

  /// Get user data (tokens, etc)
  Future<Map<String, dynamic>?> getUserData(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      return doc.data();
    } catch (e) {
      print('Error getting user data: $e');
      return null;
    }
  }

  /// Update user tokens
  Future<void> updateTokens(String userId, int tokens) async {
    try {
      await _firestore.collection('users').doc(userId).set({
        'tokens': tokens,
        'lastUpdate': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      print('Error updating tokens: $e');
    }
  }

  /// Add purchased tokens to the existing balance using a transaction
  Future<void> addTokens(String userId, int purchasedTokens) async {
    try {
      final docRef = _firestore.collection('users').doc(userId);
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(docRef);
        if (!snapshot.exists) {
          transaction.set(docRef, {
            'tokens': purchasedTokens,
            'lastUpdate': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } else {
          int currentTokens = (snapshot.data() as Map<String, dynamic>)['tokens'] ?? 0;
          transaction.update(docRef, {
            'tokens': currentTokens + purchasedTokens,
            'lastUpdate': FieldValue.serverTimestamp(),
          });
        }
      });
    } catch (e) {
      print('Error adding purchased tokens: $e');
    }
  }

  /// Check and reset daily tokens if needed
  Future<int> checkAndResetDailyTokens(String userId) async {
    try {
      final docRef = _firestore.collection('users').doc(userId);
      final doc = await docRef.get();
      
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      
      if (!doc.exists) {
        // New user, give 5000 tokens
        await docRef.set({
          'tokens': 5000,
          'lastReset': today,
        });
        return 5000;
      }

      final data = doc.data() as Map<String, dynamic>;
      final lastResetTimestamp = data['lastReset'] as Timestamp?;
      
      if (lastResetTimestamp == null || lastResetTimestamp.toDate().isBefore(today)) {
        // New day, reset to 5000
        await docRef.update({
          'tokens': 5000,
          'lastReset': today,
        });
        return 5000;
      }

      return data['tokens'] ?? 5000;
    } catch (e) {
      print('Error checking/resetting daily tokens: $e');
      return 300;
    }
  }
}
