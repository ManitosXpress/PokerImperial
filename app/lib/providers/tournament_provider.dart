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

  /// NUEVO: createTournamentPremium - Soporta scope, type y settings
  /// 🆕 UPDATED: Ahora soporta configuración avanzada de torneos
  Future<void> createTournamentPremium({
    required String name,
    required int buyIn,
    required String scope,
    required String type, // FREEZEOUT, REBUY, BOUNTY, TURBO
    required Map<String, dynamic> settings, // { rebuyAllowed, bountyAmount, blindSpeed }
    String? clubId,
    int? numberOfTables,
    String? finalTableMusic,
    String? finalTableTheme,
    // 🆕 NEW ADVANCED CONFIGURATION PARAMETERS
    String? tournamentFormat, // 'SNG' or 'MTT'
    String? blindStructureSpeed, // 'TURBO', 'REGULAR', 'DEEP'
    int? startingChips, // Default starting chip stack
    double? guaranteedPrize, // Guaranteed prize pool
    List<Map<String, dynamic>>? blindStructure, // Complete blind structure
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      // Prepare the data payload for the Cloud Function
      final Map<String, dynamic> payload = {
        'name': name,
        'buyIn': buyIn,
        'scope': scope,
        'type': type,
        'settings': settings,
        'numberOfTables': numberOfTables ?? 1,
      };

      // Add optional fields
      if (clubId != null) payload['clubId'] = clubId;
      if (finalTableMusic != null) payload['finalTableMusic'] = finalTableMusic;
      if (finalTableTheme != null) payload['finalTableTheme'] = finalTableTheme;
      
      // 🆕 Add new advanced configuration fields
      if (tournamentFormat != null) payload['tournamentFormat'] = tournamentFormat;
      if (blindStructureSpeed != null) payload['blindStructureSpeed'] = blindStructureSpeed;
      if (startingChips != null) payload['startingChips'] = startingChips;
      if (guaranteedPrize != null) payload['guaranteedPrize'] = guaranteedPrize;
      if (blindStructure != null) payload['blindStructure'] = blindStructure;

      final result = await _functions.httpsCallable('createTournamentFunction').call(payload);

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

  /// Register for a tournament
  Future<Map<String, dynamic>> registerForTournament(String tournamentId) async {
    try {
      final result = await _functions.httpsCallable('registerForTournamentFunction').call({
        'tournamentId': tournamentId,
      });

      if (result.data['success'] == true) {
        await fetchTournaments(); // Refresh list
      }

      return {
        'success': true,
        'message': result.data['message'] ?? 'Inscripción exitosa',
        'remainingCredits': result.data['remainingCredits'],
      };
    } catch (e) {
      print('Error registering for tournament: $e');
      rethrow;
    }
  }

  /// Unregister from a tournament
  Future<Map<String, dynamic>> unregisterFromTournament(String tournamentId) async {
    try {
      final result = await _functions.httpsCallable('unregisterFromTournamentFunction').call({
        'tournamentId': tournamentId,
      });

      if (result.data['success'] == true) {
        await fetchTournaments(); // Refresh list
      }

      return {
        'success': true,
        'message': result.data['message'] ?? 'Inscripción cancelada',
        'refundAmount': result.data['refundAmount'],
      };
    } catch (e) {
      print('Error unregistering from tournament: $e');
      rethrow;
    }
  }

  /// Send a chat message
  Future<void> sendMessage(String tournamentId, String message) async {
    try {
      await _functions.httpsCallable('sendTournamentMessageFunction').call({
        'tournamentId': tournamentId,
        'message': message,
      });
    } catch (e) {
      print('Error sending message: $e');
      rethrow;
    }
  }

  /// Start the tournament (Host only)
  Future<void> startTournament(String tournamentId) async {
    try {
      await _functions.httpsCallable('startTournamentFunction').call({
        'tournamentId': tournamentId,
      });
    } catch (e) {
      print('Error starting tournament: $e');
      rethrow;
    }
  }

  /// Open tournament tables for registration (Host only)
  Future<void> openTournamentTables(String tournamentId) async {
    try {
      await _functions.httpsCallable('openTournamentTablesFunction').call({
        'tournamentId': tournamentId,
      });
    } catch (e) {
      print('Error opening tournament tables: $e');
      rethrow;
    }
  }

  // ==================== GOD MODE ADMIN METHODS ====================

  /// Pause a running tournament (Admin only)
  Future<void> adminPauseTournament(String tournamentId) async {
    try {
      await _functions.httpsCallable('adminPauseTournamentFunction').call({
        'tournamentId': tournamentId,
      });
    } catch (e) {
      print('Error pausing tournament: $e');
      rethrow;
    }
  }

  /// Resume a paused tournament (Admin only)
  Future<void> adminResumeTournament(String tournamentId) async {
    try {
      await _functions.httpsCallable('adminResumeTournamentFunction').call({
        'tournamentId': tournamentId,
      });
    } catch (e) {
      print('Error resuming tournament: $e');
      rethrow;
    }
  }

  /// Force increment blind level (Admin only)
  Future<Map<String, dynamic>> adminForceBlindLevel(String tournamentId) async {
    try {
      final result = await _functions.httpsCallable('adminForceBlindLevelFunction').call({
        'tournamentId': tournamentId,
      });
      return Map<String, dynamic>.from(result.data);
    } catch (e) {
      print('Error forcing blind level: $e');
      rethrow;
    }
  }

  /// Broadcast admin message to all tournament participants (Admin only)
  Future<void> adminBroadcastMessage(String tournamentId, String message) async {
    try {
      await _functions.httpsCallable('adminBroadcastMessageFunction').call({
        'tournamentId': tournamentId,
        'message': message,
      });
    } catch (e) {
      print('Error broadcasting message: $e');
      rethrow;
    }
  }
}
