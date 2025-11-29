import 'package:flutter/material.dart';

class ClubProvider with ChangeNotifier {
  List<Map<String, dynamic>> _clubs = [];
  Map<String, dynamic>? _myClub;
  bool _isLoading = false;

  List<Map<String, dynamic>> get clubs => _clubs;
  Map<String, dynamic>? get myClub => _myClub;
  bool get isLoading => _isLoading;

  // Mock data for now - replace with API calls later
  Future<void> fetchClubs() async {
    _isLoading = true;
    notifyListeners();

    await Future.delayed(const Duration(seconds: 1)); // Simulate network

    _clubs = [
      {
        'id': '1',
        'name': 'Royal Flush Club',
        'description': 'Elite players only',
        'memberCount': 120,
      },
      {
        'id': '2',
        'name': 'Shark Tank',
        'description': 'High stakes games',
        'memberCount': 45,
      },
      {
        'id': '3',
        'name': 'Beginners Luck',
        'description': 'Learning together',
        'memberCount': 300,
      },
    ];

    _isLoading = false;
    notifyListeners();
  }

  Future<void> createClub(String name, String description) async {
    _isLoading = true;
    notifyListeners();

    await Future.delayed(const Duration(seconds: 1));

    final newClub = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'name': name,
      'description': description,
      'memberCount': 1,
      'isOwner': true,
    };

    _myClub = newClub;
    _clubs.add(newClub);

    _isLoading = false;
    notifyListeners();
  }

  Future<void> joinClub(String clubId) async {
    _isLoading = true;
    notifyListeners();

    await Future.delayed(const Duration(seconds: 1));

    _myClub = _clubs.firstWhere((c) => c['id'] == clubId);

    _isLoading = false;
    notifyListeners();
  }
}
