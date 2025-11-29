import 'package:flutter/material.dart';

class TournamentProvider with ChangeNotifier {
  List<Map<String, dynamic>> _tournaments = [];
  bool _isLoading = false;

  List<Map<String, dynamic>> get tournaments => _tournaments;
  bool get isLoading => _isLoading;

  Future<void> fetchTournaments() async {
    _isLoading = true;
    notifyListeners();

    await Future.delayed(const Duration(seconds: 1));

    _tournaments = [
      {
        'id': '101',
        'name': 'Weekly Sunday Million',
        'buyIn': 100,
        'prizePool': 10000,
        'startTime': DateTime.now().add(const Duration(days: 2)).toString(),
        'type': 'Open',
      },
      {
        'id': '102',
        'name': 'Club vs Club Showdown',
        'buyIn': 500,
        'prizePool': 50000,
        'startTime': DateTime.now().add(const Duration(hours: 5)).toString(),
        'type': 'Inter-club',
      },
    ];

    _isLoading = false;
    notifyListeners();
  }

  Future<void> createTournament(String name, int buyIn, String type) async {
    _isLoading = true;
    notifyListeners();

    await Future.delayed(const Duration(seconds: 1));

    _tournaments.add({
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'name': name,
      'buyIn': buyIn,
      'prizePool': buyIn * 10, // Mock prize pool
      'startTime': DateTime.now().add(const Duration(hours: 24)).toString(),
      'type': type,
    });

    _isLoading = false;
    notifyListeners();
  }
}
