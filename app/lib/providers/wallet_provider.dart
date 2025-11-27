import 'package:flutter/foundation.dart';
import '../services/credits_service.dart';

/// Wallet Provider
/// Manages wallet state and credit operations throughout the app
class WalletProvider extends ChangeNotifier {
  final CreditsService _creditsService = CreditsService();

  double _balance = 0;
  double _inGameBalance = 0;
  bool _isLoading = false;
  String? _errorMessage;

  double get balance => _balance;
  double get inGameBalance => _inGameBalance;
  double get totalBalance => _balance + _inGameBalance;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Initialize wallet and listen to balance changes
  void initialize() {
    _creditsService.getWalletBalanceStream().listen(
      (balance) {
        _balance = balance;
        notifyListeners();
      },
      onError: (error) {
        _errorMessage = error.toString();
        notifyListeners();
      },
    );

    _creditsService.getInGameBalanceStream().listen(
      (balance) {
        _inGameBalance = balance;
        notifyListeners();
      },
      onError: (error) {
        print('Error getting in-game balance: $error');
      },
    );
  }

  /// Add credits (simulates purchase)
  Future<bool> addCredits(double amount, String reason) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final newBalance = await _creditsService.addCredits(
        amount: amount,
        reason: reason,
      );
      _balance = newBalance;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Deduct credits (for game entry or purchases)
  Future<bool> deductCredits(
    double amount,
    String reason, {
    Map<String, dynamic>? metadata,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final newBalance = await _creditsService.deductCredits(
        amount: amount,
        reason: reason,
        metadata: metadata,
      );
      _balance = newBalance;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Get transaction history
  Stream<List<TransactionLog>> getTransactionHistory() {
    return _creditsService.getTransactionHistoryStream();
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
