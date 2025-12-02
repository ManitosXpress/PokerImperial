import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ClubProvider with ChangeNotifier {
  List<Map<String, dynamic>> _clubs = [];
  Map<String, dynamic>? _myClub;
  bool _isLoading = false;
  String? _errorMessage;

  List<Map<String, dynamic>> get clubs => _clubs;
  Map<String, dynamic>? get myClub => _myClub;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> fetchClubs() async {
    _isLoading = true;
    notifyListeners();

    try {
      // Fetch all clubs
      final snapshot = await _firestore.collection('clubs').get();
      _clubs = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      // Check if user has a club
      final userDoc = await _firestore.collection('users').doc(_auth.currentUser?.uid).get();
      final clubId = userDoc.data()?['clubId'];

      if (clubId != null) {
        final myClubDoc = await _firestore.collection('clubs').doc(clubId).get();
        if (myClubDoc.exists) {
          _myClub = myClubDoc.data();
          _myClub!['id'] = myClubDoc.id;
        }
      } else {
        _myClub = null;
      }

    } catch (e) {
      print('Error fetching clubs: $e');
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> createClub(String name, String description) async {
    _isLoading = true;
    notifyListeners();

    try {
      final result = await _functions.httpsCallable('createClubFunction').call({
        'name': name,
        'description': description,
      });

      if (result.data['success'] == true) {
        await fetchClubs(); // Refresh list
      }
    } catch (e) {
      print('Error creating club: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> joinClub(String clubId) async {
    _isLoading = true;
    notifyListeners();

    try {
      final result = await _functions.httpsCallable('joinClubFunction').call({
        'clubId': clubId,
      });

      if (result.data['success'] == true) {
        await fetchClubs(); // Refresh list
      }
    } catch (e) {
      print('Error joining club: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<List<Map<String, dynamic>>> fetchClubTournaments(String clubId) async {
    print('🔍 Fetching tournaments for clubId: "$clubId" (Length: ${clubId.length})');
    try {
      // Try with ordering first (requires index)
      final snapshot = await _firestore
          .collection('tournaments')
          .where('clubId', isEqualTo: clubId)
          .orderBy('createdAt', descending: true)
          .get();
      print('✅ Found ${snapshot.docs.length} tournaments with sorted query.');
      return snapshot.docs.map((doc) => doc.data()).toList();
    } catch (e) {
      print('❌ Error fetching club tournaments with sort: $e');
      
      // Fallback: Try without ordering (no index required usually for simple equality)
      try {
        print('⚠️ Attempting fallback fetch without sorting...');
        final snapshot = await _firestore
            .collection('tournaments')
            .where('clubId', isEqualTo: clubId)
            .get();
        
        print('✅ Found ${snapshot.docs.length} tournaments with fallback query.');
        
        // Sort manually in memory
        final docs = snapshot.docs.map((doc) => doc.data()).toList();
        docs.sort((a, b) {
          final aTime = (a['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
          final bTime = (b['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
          return bTime.compareTo(aTime);
        });
        
        return docs;
      } catch (e2) {
        print('❌ Error fetching club tournaments fallback: $e2');
        return [];
      }
    }
  }

  Future<List<Map<String, dynamic>>> fetchClubLeaderboard(String clubId) async {
    try {
      print('📊 Fetching leaderboard for club: $clubId');
      
      final result = await _functions.httpsCallable('getClubLeaderboardFunction').call({
        'clubId': clubId,
      });
      
      print('📊 Raw result from Cloud Function: ${result.data}');
      
      if (result.data == null) {
        print('⚠️ Received null data from Cloud Function');
        return [];
      }
      
      if (result.data['leaderboard'] == null) {
        print('⚠️ Leaderboard field is null in the response');
        return [];
      }
      
      final List<dynamic> data = result.data['leaderboard'];
      print('📊 Leaderboard has ${data.length} members');
      
      return data.cast<Map<String, dynamic>>();
    } catch (e, stackTrace) {
      print('❌ Error fetching club leaderboard: $e');
      print('Stack trace: $stackTrace');
      
      // Check if it's a Firestore index error
      if (e.toString().contains('index') || e.toString().contains('requires an index')) {
        throw Exception('Firestore index required. Please check Firebase Console for the index creation link.');
      }
      
      rethrow; // Propagate error to UI
    }
  }

  Future<void> transferClubToMember(String clubId, String memberId, int amount) async {
    _isLoading = true;
    notifyListeners();

    try {
      final result = await _functions.httpsCallable('transferClubToMemberFunction').call({
        'clubId': clubId,
        'memberId': memberId,
        'amount': amount,
      });

      if (result.data['success'] == true) {
        // Refresh club data to show new balance
        await fetchClubs();
      }
    } catch (e) {
      print('Error transferring credits: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
