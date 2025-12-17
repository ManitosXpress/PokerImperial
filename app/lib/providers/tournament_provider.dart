import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class TournamentProvider with ChangeNotifier {
  List<Map<String, dynamic>> _tournaments = [];
  bool _isLoading = false;

  List<Map<String, dynamic>> get tournaments => _tournaments;
  bool get isLoading => _isLoading;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  Future<void> fetchTournaments() async {
    _isLoading = true;
    notifyListeners();

    try {
      final snapshot = await _firestore.collection('tournaments').orderBy('createdAt', descending: true).get();
      _tournaments = snapshot.docs.map((doc) => doc.data()).toList();
    } catch (e) {
      print('Error fetching tournaments: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> createTournament(String name, int buyIn, String type, {String? clubId}) async {
    _isLoading = true;
    notifyListeners();

    try {
      final result = await _functions.httpsCallable('createTournamentFunction').call({
        'name': name,
        'buyIn': buyIn,
        'type': type,
        'clubId': clubId,
      });

      if (result.data['success'] == true) {
        await fetchTournaments(); // Refresh list
      }
    } catch (e) {
      print('Error creating tournament: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// NUEVO: createTournamentPremium - Soporta scope, speed y configuración Pro
  Future<void> createTournamentPremium({
    required String name,
    required int buyIn,
    required String scope,
    required String speed,
    String? clubId,
    int? estimatedPlayers,
    String? finalTableMusic,
    String? finalTableTheme,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      final result = await _functions.httpsCallable('createTournamentFunction').call({
        'name': name,
        'buyIn': buyIn,
        'scope': scope,
        'speed': speed,
        'clubId': clubId,
        'estimatedPlayers': estimatedPlayers ?? 10,
        'finalTableMusic': finalTableMusic,
        'finalTableTheme': finalTableTheme,
      });

      if (result.data['success'] == true) {
        await fetchTournaments(); // Refresh list
      }
    } catch (e) {
      print('Error creating tournament: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
