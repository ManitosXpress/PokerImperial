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
      _clubs = snapshot.docs.map((doc) => doc.data()).toList();

      // Check if user has a club
      final userDoc = await _firestore.collection('users').doc(_auth.currentUser?.uid).get();
      final clubId = userDoc.data()?['clubId'];

      if (clubId != null) {
        final myClubDoc = await _firestore.collection('clubs').doc(clubId).get();
        if (myClubDoc.exists) {
          _myClub = myClubDoc.data();
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
    try {
      final snapshot = await _firestore
          .collection('tournaments')
          .where('clubId', isEqualTo: clubId)
          .orderBy('createdAt', descending: true)
          .get();
      return snapshot.docs.map((doc) => doc.data()).toList();
    } catch (e) {
      print('Error fetching club tournaments: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchClubLeaderboard(String clubId) async {
    try {
      final result = await _functions.httpsCallable('getClubLeaderboardFunction').call({
        'clubId': clubId,
      });
      
      final List<dynamic> data = result.data['leaderboard'];
      return data.cast<Map<String, dynamic>>();
    } catch (e) {
      print('Error fetching club leaderboard: $e');
      return [];
    }
  }
}
