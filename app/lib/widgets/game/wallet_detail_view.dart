import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../providers/wallet_provider.dart';
import 'dart:ui';
import 'package:intl/intl.dart';

/// Wallet Detail View - Bottom Sheet with Transaction History
class WalletDetailView extends StatelessWidget {
  const WalletDetailView({super.key});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(30),
              topRight: Radius.circular(30),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(30),
              topRight: Radius.circular(30),
            ),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFF1A1A2E).withOpacity(0.95),
                      const Color(0xFF0F0F1E).withOpacity(0.98),
                    ],
                  ),
                ),
                child: Column(
                  children: [
                    // Handle bar
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      width: 50,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),

                    // Header
                    _buildHeader(context),

                    // Transaction List
                    Expanded(
                      child: _buildTransactionList(context, scrollController),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Consumer<WalletProvider>(
      builder: (context, walletProvider, child) {
        final totalBalance = walletProvider.totalBalance;
        final balance = walletProvider.balance;
        final inGameBalance = walletProvider.inGameBalance;

        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFFFFD700).withOpacity(0.2),
                const Color(0xFF8B7500).withOpacity(0.1),
              ],
            ),
            border: Border(
              bottom: BorderSide(
                color: const Color(0xFFFFD700).withOpacity(0.3),
                width: 1,
              ),
            ),
          ),
          child: Column(
            children: [
              // Title
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.account_balance_wallet_rounded,
                    color: Color(0xFFFFD700),
                    size: 28,
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Mi Billetera',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Balance Display
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFFFFD700).withOpacity(0.15),
                      const Color(0xFF8B7500).withOpacity(0.05),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFFFFD700).withOpacity(0.3),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Saldo Total',
                      style: TextStyle(
                        color: Color(0xFFFFD700),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      totalBalance.toStringAsFixed(0),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 42,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'RobotoMono',
                        letterSpacing: 2,
                        shadows: [
                          Shadow(
                            color: Color(0xFFFFD700),
                            blurRadius: 20,
                          ),
                        ],
                      ),
                    ),

                    // Breakdown
                    if (inGameBalance > 0) ...[
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildBalanceItem(
                            'Disponible',
                            balance,
                            Icons.wallet,
                            const Color(0xFF00FF88),
                          ),
                          Container(
                            width: 1,
                            height: 30,
                            color: Colors.white.withOpacity(0.2),
                          ),
                          _buildBalanceItem(
                            'En Mesa',
                            inGameBalance,
                            Icons.casino,
                            const Color(0xFFFFD700),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBalanceItem(
      String label, double amount, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          amount.toStringAsFixed(0),
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            fontFamily: 'RobotoMono',
          ),
        ),
      ],
    );
  }

  Widget _buildTransactionList(
      BuildContext context, ScrollController scrollController) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(
        child: Text(
          'Usuario no autenticado',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    // Llamar a la Cloud Function para obtener todas las transacciones
    return FutureBuilder<Map<String, dynamic>>(
      future: _fetchTransactionHistory(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFFD700)),
            ),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.red.withOpacity(0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  'Error al cargar transacciones',
                  style: TextStyle(
                    color: Colors.red.withOpacity(0.8),
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${snapshot.error}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        final transactions = (snapshot.data?['transactions'] as List<dynamic>?)
                ?.cast<Map<String, dynamic>>() ??
            [];

        if (transactions.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.receipt_long_outlined,
                  size: 64,
                  color: Colors.white.withOpacity(0.3),
                ),
                const SizedBox(height: 16),
                Text(
                  'Sin transacciones aún',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            // Recargar transacciones
            // El FutureBuilder se actualizará automáticamente
          },
          color: const Color(0xFFFFD700),
          child: ListView.builder(
            controller: scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: transactions.length,
            itemBuilder: (context, index) {
              final transaction = transactions[index];
              return _buildTransactionItem(transaction);
            },
          ),
        );
      },
    );
  }

  // Función para llamar a la Cloud Function
  Future<Map<String, dynamic>> _fetchTransactionHistory() async {
    try {
      final functions = FirebaseFunctions.instance;
      final result = await functions.httpsCallable('getUserTransactionHistoryFunction').call({
        'limit': 100,
      });

      return result.data as Map<String, dynamic>;
    } catch (e) {
      print('Error fetching transaction history: $e');
      rethrow;
    }
  }

  Widget _buildTransactionItem(Map<String, dynamic> transaction) {
    final type = transaction['type'] as String? ?? 'unknown';
    final source = transaction['source'] as String? ?? 'transaction_logs';
    
    // Obtener amount según la fuente
    double amount = 0.0;
    if (source == 'financial_ledger') {
      // financial_ledger usa 'amount' directamente
      amount = (transaction['amount'] as num?)?.toDouble() ?? 0.0;
      // Si es GAME_WIN/GAME_LOSS, usar netAmount si existe
      if ((type == 'GAME_WIN' || type == 'GAME_LOSS') && transaction['netAmount'] != null) {
        amount = (transaction['netAmount'] as num).toDouble();
      }
    } else {
      // transaction_logs usa 'amount'
      amount = (transaction['amount'] as num?)?.toDouble() ?? 0.0;
    }
    
    final reason = transaction['reason'] as String? ?? transaction['description'] as String? ?? 'Sin descripción';
    final timestamp = transaction['timestamp'] as Timestamp?;
    final metadata = transaction['metadata'] as Map<String, dynamic>?;
    final tableId = transaction['tableId'] as String?;

    // Determine transaction direction
    bool isPositive = false;
    IconData icon;
    Color iconColor;
    String title;

    switch (type) {
      // Transacciones positivas (entradas)
      case 'credit':
      case 'deposit':
      case 'win':
      case 'game_win':
      case 'GAME_WIN':
      case 'refund':
      case 'admin_credit':
      case 'ADMIN_MINT':
      case 'REPAIR_REFUND':
      case 'WIN_PRIZE':
        isPositive = true;
        icon = Icons.arrow_upward_rounded;
        iconColor = const Color(0xFF00FF88);
        title = _getTransactionTitle(type, reason, metadata, tableId);
        break;

      // Transacciones negativas (salidas)
      case 'debit':
      case 'withdrawal':
      case 'loss':
      case 'game_loss':
      case 'GAME_LOSS':
      case 'game_entry':
      case 'purchase':
      case 'CASHOUT':
        isPositive = false;
        icon = Icons.arrow_downward_rounded;
        iconColor = const Color(0xFFFF4444);
        title = _getTransactionTitle(type, reason, metadata, tableId);
        break;

      default:
        // Por defecto, si amount es positivo, es entrada
        isPositive = amount >= 0;
        icon = isPositive ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded;
        iconColor = isPositive ? const Color(0xFF00FF88) : const Color(0xFFFF4444);
        title = _getTransactionTitle(type, reason, metadata, tableId);
    }

    // Format date
    String dateStr = 'Desconocido';
    if (timestamp != null) {
      final date = timestamp.toDate();
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inDays == 0) {
        dateStr = 'Hoy, ${DateFormat('HH:mm').format(date)}';
      } else if (diff.inDays == 1) {
        dateStr = 'Ayer, ${DateFormat('HH:mm').format(date)}';
      } else if (diff.inDays < 7) {
        dateStr = DateFormat('EEEE, HH:mm', 'es').format(date);
      } else {
        dateStr = DateFormat('dd/MM/yyyy, HH:mm').format(date);
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.05),
            Colors.white.withOpacity(0.02),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // Icon
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  iconColor.withOpacity(0.3),
                  iconColor.withOpacity(0.1),
                ],
              ),
              border: Border.all(
                color: iconColor.withOpacity(0.5),
                width: 2,
              ),
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 24,
            ),
          ),

          const SizedBox(width: 16),

          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  dateStr,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          // Amount
          Text(
            '${isPositive ? '+' : '-'}${amount.abs().toStringAsFixed(0)}',
            style: TextStyle(
              color: isPositive ? const Color(0xFF00FF88) : const Color(0xFFFF4444),
              fontSize: 18,
              fontWeight: FontWeight.bold,
              fontFamily: 'RobotoMono',
            ),
          ),
        ],
      ),
    );
  }

  String _getTransactionTitle(
      String type, String reason, Map<String, dynamic>? metadata, String? tableId) {
    // Si hay tableId, mostrar información de la mesa
    if (tableId != null && tableId.isNotEmpty) {
      return 'Mesa: ${tableId.substring(0, tableId.length > 12 ? 12 : tableId.length)}...';
    }

    // Si hay metadata con roomId
    if (metadata != null && metadata['roomId'] != null) {
      final roomId = metadata['roomId'] as String;
      return 'Mesa: ${roomId.length > 12 ? roomId.substring(0, 12) + '...' : roomId}';
    }

    // Títulos según tipo de transacción
    switch (type) {
      // Cargas y depósitos
      case 'credit':
      case 'admin_credit':
      case 'ADMIN_MINT':
        return 'Carga Admin';
      case 'deposit':
        return 'Depósito';
      
      // Victorias
      case 'win':
      case 'game_win':
      case 'GAME_WIN':
      case 'WIN_PRIZE':
        return 'Ganancia en Mesa';
      
      // Pérdidas
      case 'loss':
      case 'game_loss':
      case 'GAME_LOSS':
        return 'Pérdida en Mesa';
      
      // Reembolsos y reparaciones
      case 'refund':
        return 'Reembolso';
      case 'REPAIR_REFUND':
        return 'Reparación de Sesión';
      
      // Retiros y débitos
      case 'debit':
        return 'Débito';
      case 'withdrawal':
        return 'Retiro';
      case 'CASHOUT':
        return 'Cashout de Mesa';
      
      // Entradas y compras
      case 'game_entry':
        return 'Entrada a Partida';
      case 'purchase':
        return 'Compra';
      
      // Transferencias (si las hay)
      case 'transfer':
      case 'TRANSFER':
        return 'Transferencia';
      
      default:
        // Si no hay título específico, usar reason o description
        return reason.isNotEmpty ? reason : 'Transacción';
    }
  }
}

