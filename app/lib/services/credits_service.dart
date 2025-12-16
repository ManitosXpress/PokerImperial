import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Credits Service
/// Handles all credit-related operations through Cloud Functions
/// Implements server-authoritative architecture
class CreditsService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Get real-time wallet balance stream
  /// Listens to Firestore for balance updates
  Stream<double> getWalletBalanceStream() {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      return Stream.value(0);
    }

    return _firestore
        .collection('users')
        .doc(userId)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return 0.0;
      return (doc.data()?['credit'] ?? 0).toDouble(); // Changed from walletBalance
    });
  }

  /// Get current wallet balance (one-time read)
  Future<double> getWalletBalance() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return 0;

    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      if (!doc.exists) return 0;
      return (doc.data()?['credit'] ?? 0).toDouble(); // Changed from walletBalance
    } catch (e) {
      print('Error getting wallet balance: $e');
      return 0;
    }
  }

  /// Add credits through Cloud Function
  /// This simulates a purchase or blockchain deposit
  /// 
  /// @param amount - Amount of credits to add
  /// @param reason - Reason for adding credits (e.g., 'purchase', 'reward')
  /// @returns New balance after adding credits
  Future<double> addCredits({
    required double amount,
    required String reason,
  }) async {
    try {
      // Call Cloud Function
      final HttpsCallable callable =
          _functions.httpsCallable('addCreditsFunction');

      final result = await callable.call<Map<String, dynamic>>({
        'amount': amount,
        'reason': reason,
      });

      // Extract new balance from result
      final data = result.data;
      return (data['newBalance'] ?? 0).toDouble();
    } on FirebaseFunctionsException catch (e) {
      throw _handleFunctionException(e);
    } catch (e) {
      throw Exception('Error adding credits: ${e.toString()}');
    }
  }

  /// Deduct credits through Cloud Function
  /// This is called when joining a game table or making purchases
  /// 
  /// @param amount - Amount of credits to deduct
  /// @param reason - Reason for deducting (e.g., 'game_entry', 'purchase')
  /// @param metadata - Optional metadata (gameId, tableId, etc.)
  /// @returns New balance after deducting credits
  /// @throws Exception if insufficient balance
  Future<double> deductCredits({
    required double amount,
    required String reason,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      // Call Cloud Function
      final HttpsCallable callable =
          _functions.httpsCallable('deductCreditsFunction');

      final result = await callable.call<Map<String, dynamic>>({
        'amount': amount,
        'reason': reason,
        if (metadata != null) 'metadata': metadata,
      });

      // Extract new balance from result
      final data = result.data;
      return (data['newBalance'] ?? 0).toDouble();
    } on FirebaseFunctionsException catch (e) {
      throw _handleFunctionException(e);
    } catch (e) {
      throw Exception('Error deducting credits: ${e.toString()}');
    }
  }

  /// Get transaction history stream
  /// Returns real-time stream of user's transaction logs
  Stream<List<TransactionLog>> getTransactionHistoryStream() {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      return Stream.value([]);
    }

    return _firestore
        .collection('transaction_logs')
        .where('userId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return TransactionLog.fromFirestore(doc);
      }).toList();
    });
  }

  /// Get in-game (reserved) balance stream
  /// ✅ CORREGIDO: Usa Cloud Function del backend para calcular desde poker_sessions
  /// El backend calcula dinámicamente desde poker_sessions (fuente de verdad)
  /// Esto mantiene la lógica del negocio en el backend
  /// 
  /// Para streams en tiempo real, escuchamos cambios en poker_sessions (solo lectura)
  /// y cuando detectamos cambios, llamamos a la Cloud Function del backend
  Stream<double> getInGameBalanceStream() {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      return Stream.value(0);
    }

    // ✅ CORRECCIÓN: El frontend solo escucha cambios (solo lectura)
    // Cuando hay cambios, llama a la Cloud Function del backend para obtener el cálculo autoritativo
    // Esto mantiene la lógica del negocio en el backend
    return _firestore
        .collection('poker_sessions')
        .where('userId', isEqualTo: userId)
        .where('status', isEqualTo: 'active')
        .snapshots()
        .asyncMap((snapshot) async {
      // Llamar a la Cloud Function del backend para obtener el cálculo autoritativo
      try {
        final callable = _functions.httpsCallable('getInGameBalanceFunction');
        final result = await callable.call<Map<String, dynamic>>();
        final moneyInPlay = (result.data['moneyInPlay'] ?? 0).toDouble();
        final sessionCount = result.data['sessionCount'] ?? 0;
        
        print('[IN_GAME_BALANCE] ✅ MoneyInPlay desde backend: $moneyInPlay (${sessionCount} sesión/es)');
        return moneyInPlay;
      } catch (e) {
        print('[IN_GAME_BALANCE] ❌ Error llamando a getInGameBalanceFunction: $e');
        // Fallback: calcular localmente si falla la Cloud Function (solo para resiliencia)
        if (snapshot.docs.isEmpty) {
          print('[IN_GAME_BALANCE] ⚠️ Fallback: No hay sesiones activas');
          return 0.0;
        }
        double total = 0.0;
        for (final doc in snapshot.docs) {
          final buyInAmount = (doc.data()['buyInAmount'] ?? 0).toDouble();
          total += buyInAmount;
        }
        print('[IN_GAME_BALANCE] ⚠️ Fallback: Calculado localmente: $total');
        return total;
      }
    });
  }

  /// Handle Cloud Functions exceptions
  String _handleFunctionException(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'unauthenticated':
        return 'Debes iniciar sesión para realizar esta acción.';
      case 'permission-denied':
        return 'No tienes permiso para realizar esta acción.';
      case 'invalid-argument':
        return 'Datos inválidos: ${e.message}';
      case 'failed-precondition':
        return e.message ?? 'Saldo insuficiente.';
      default:
        return 'Error: ${e.message ?? e.code}';
    }
  }

  /// Withdraw credits through Cloud Function
  /// This simulates a withdrawal to a blockchain wallet
  /// 
  /// @param amount - Amount of credits to withdraw
  /// @param walletAddress - Destination wallet address
  /// @returns New balance after withdrawing credits
  Future<double> withdrawCredits({
    required double amount,
    required String walletAddress,
  }) async {
    try {
      // Call Cloud Function
      final HttpsCallable callable =
          _functions.httpsCallable('withdrawCreditsFunction');

      final result = await callable.call<Map<String, dynamic>>({
        'amount': amount,
        'walletAddress': walletAddress,
      });

      // Extract new balance from result
      final data = result.data;
      return (data['newBalance'] ?? 0).toDouble();
    } on FirebaseFunctionsException catch (e) {
      throw _handleFunctionException(e);
    } catch (e) {
      throw Exception('Error withdrawing credits: ${e.toString()}');
    }
  }
}

/// Transaction Log Model
class TransactionLog {
  final String id;
  final String userId;
  final double amount;
  final String type; // 'credit' or 'debit'
  final String reason;
  final DateTime timestamp;
  final double beforeBalance;
  final double afterBalance;
  final String hash;
  final Map<String, dynamic>? metadata;

  TransactionLog({
    required this.id,
    required this.userId,
    required this.amount,
    required this.type,
    required this.reason,
    required this.timestamp,
    required this.beforeBalance,
    required this.afterBalance,
    required this.hash,
    this.metadata,
  });

  factory TransactionLog.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return TransactionLog(
      id: doc.id,
      userId: data['userId'] ?? '',
      amount: (data['amount'] ?? 0).toDouble(),
      type: data['type'] ?? '',
      reason: data['reason'] ?? '',
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      beforeBalance: (data['beforeBalance'] ?? 0).toDouble(),
      afterBalance: (data['afterBalance'] ?? 0).toDouble(),
      hash: data['hash'] ?? '',
      metadata: data['metadata'] as Map<String, dynamic>?,
    );
  }
}
