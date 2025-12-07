import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../widgets/poker_loading_indicator.dart';

class TransactionHistoryScreen extends StatelessWidget {
  const TransactionHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Please login to view history')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('HISTORIAL DE TRANSACCIONES', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        backgroundColor: const Color(0xFF1A1A2E),
        centerTitle: true,
        elevation: 0,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
          ),
        ),
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('financial_ledger')
              .where('userId', isEqualTo: user.uid)
              .orderBy('timestamp', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: PokerLoadingIndicator(
                  statusText: 'Cargando historial...',
                  color: Color(0xFFFFD700),
                ),
              );
            }

            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 48),
                    const SizedBox(height: 16),
                    Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.white70)),
                  ],
                ),
              );
            }

            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.history, size: 64, color: Colors.white.withOpacity(0.2)),
                    const SizedBox(height: 16),
                    const Text(
                      'No hay transacciones recientes',
                      style: TextStyle(color: Colors.white54, fontSize: 18),
                    ),
                  ],
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: snapshot.data!.docs.length,
              itemBuilder: (context, index) {
                final doc = snapshot.data!.docs[index];
                final data = doc.data() as Map<String, dynamic>;
                final type = data['type'] ?? 'UNKNOWN';
                final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
                final timestamp = (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
                final description = data['description'] ?? 'Sin descripción';
                
                // Determine visual style based on type/amount
                // Assuming 'credit' types are positive, 'debit' are negative, or checking amount sign if stored signed.
                // Usually ledger stores absolute amount and type.
                // Let's infer: DEPOSIT, WIN, TRANSFER_IN -> Green
                // WITHDRAW, LOSS, TRANSFER_OUT -> Red
                
                bool isPositive = false;
                IconData icon = Icons.help_outline;
                
                if (type == 'DEPOSIT_BOT' || type == 'credit' || type == 'WIN_PRIZE' || type == 'TRANSFER_IN') {
                  isPositive = true;
                  icon = Icons.arrow_downward; // Money coming in
                } else {
                  isPositive = false;
                  icon = Icons.arrow_upward; // Money going out
                }
                
                // Specific icons
                if (type == 'WIN_PRIZE') icon = Icons.emoji_events;
                if (type == 'DEPOSIT_BOT') icon = Icons.account_balance_wallet;

                final color = isPositive ? Colors.greenAccent : Colors.redAccent;
                final sign = isPositive ? '+' : '-';

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: color, size: 20),
                    ),
                    title: Text(
                      description,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      DateFormat('dd MMM yyyy, HH:mm').format(timestamp),
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    trailing: Text(
                      '$sign${amount.toStringAsFixed(0)}',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
