import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../widgets/poker_loading_indicator.dart';

class FinanceHistoryView extends StatelessWidget {
  const FinanceHistoryView({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'Historial de Transacciones',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('financial_ledger')
                .orderBy('timestamp', descending: true)
                .limit(50)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
              }
              if (!snapshot.hasData) {
                return const Center(child: PokerLoadingIndicator(size: 40, color: Colors.amber));
              }

              final docs = snapshot.data!.docs;

              if (docs.isEmpty) {
                return const Center(child: Text('No hay transacciones registradas.', style: TextStyle(color: Colors.white54)));
              }

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  child: DataTable(
                    headingRowColor: MaterialStateProperty.all(Colors.white10),
                    dataRowColor: MaterialStateProperty.all(Colors.transparent),
                    columns: const [
                      DataColumn(label: Text('Fecha', style: TextStyle(color: Colors.amber))),
                      DataColumn(label: Text('Usuario (UID)', style: TextStyle(color: Colors.amber))),
                      DataColumn(label: Text('Monto', style: TextStyle(color: Colors.amber))),
                      DataColumn(label: Text('Tipo', style: TextStyle(color: Colors.amber))),
                      DataColumn(label: Text('Detalles', style: TextStyle(color: Colors.amber))),
                    ],
                    rows: docs.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final timestamp = (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
                      final formattedDate = DateFormat('dd/MM/yyyy HH:mm').format(timestamp);
                      final amount = data['amount'] ?? 0;
                      final type = data['type'] ?? 'UNKNOWN';
                      final userId = data['toId'] ?? 'Unknown';
                      final details = data['details'] ?? '-';

                      Color typeColor = Colors.white;
                      if (type == 'ADMIN_MINT') typeColor = Colors.greenAccent;
                      if (type == 'DEPOSIT_BOT') typeColor = Colors.blueAccent;

                      return DataRow(cells: [
                        DataCell(Text(formattedDate, style: const TextStyle(color: Colors.white70))),
                        DataCell(Text(userId, style: const TextStyle(color: Colors.white70, fontSize: 12))),
                        DataCell(Text('\$${amount.toString()}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold))),
                        DataCell(Text(type, style: TextStyle(color: typeColor, fontWeight: FontWeight.bold))),
                        DataCell(Text(details, style: const TextStyle(color: Colors.white54))),
                      ]);
                    }).toList(),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
