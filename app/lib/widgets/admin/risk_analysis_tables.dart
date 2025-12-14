import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RiskAnalysisTables extends StatelessWidget {
  const RiskAnalysisTables({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildTableSection(
          title: '🐋 The Whales (Top Holders)',
          icon: Icons.account_balance_wallet,
          color: Colors.blueAccent,
          query: FirebaseFirestore.instance.collection('users').orderBy('credit', descending: true).limit(10),
          columns: ['Usuario', 'Saldo'],
          rowBuilder: (data) {
            return [
              DataCell(Text(data['displayName'] ?? 'Unknown', style: const TextStyle(color: Colors.white))),
              DataCell(Text('\$${data['credit'] ?? 0}', style: const TextStyle(color: Colors.greenAccent))),
            ];
          },
        ),
        const SizedBox(height: 24),
        _buildTableSection(
          title: '🦈 The Sharks (Mayores Ganadores 24h)',
          icon: Icons.trending_up,
          color: Colors.redAccent,
          // Obtiene todos los GAME_WIN sin orderBy para evitar necesidad de índice, luego ordena en memoria
          query: FirebaseFirestore.instance.collection('financial_ledger')
              .where('type', isEqualTo: 'GAME_WIN')
              .limit(500), // Obtener más documentos para luego ordenar por netProfit
          columns: ['Usuario', 'Ganancia Neta', 'Mesa'],
          rowBuilder: (data) {
            return [
              DataCell(Text(data['userName'] ?? data['userId'] ?? 'Unknown', style: const TextStyle(color: Colors.white))),
              DataCell(Text('+\$${data['netProfit'] ?? 0}', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold))),
              DataCell(Text(data['tableId'] ?? '-', style: const TextStyle(color: Colors.white54))),
            ];
          },
          // Función personalizada para ordenar los resultados por netProfit después de obtenerlos
          // También filtra por las últimas 24 horas y toma los top 10
          customSort: (List<QueryDocumentSnapshot> docs) {
            final now = DateTime.now();
            final yesterday = now.subtract(const Duration(hours: 24));
            
            // Filtrar por últimas 24 horas y ordenar por netProfit
            final filtered = docs.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final timestamp = data['timestamp'];
              if (timestamp == null) return false;
              
              DateTime docTime;
              if (timestamp is Timestamp) {
                docTime = timestamp.toDate();
              } else {
                return false;
              }
              
              return docTime.isAfter(yesterday);
            }).toList();
            
            // Ordenar por netProfit descendente
            filtered.sort((a, b) {
              final dataA = a.data() as Map<String, dynamic>;
              final dataB = b.data() as Map<String, dynamic>;
              final profitA = (dataA['netProfit'] as num?)?.toDouble() ?? 0.0;
              final profitB = (dataB['netProfit'] as num?)?.toDouble() ?? 0.0;
              return profitB.compareTo(profitA); // Descendente
            });
            
            return filtered.take(10).toList(); // Tomar solo los top 10
          },
        ),
      ],
    );
  }

  Widget _buildTableSection({
    required String title,
    required IconData icon,
    required Color color,
    required Query query,
    required List<String> columns,
    required List<DataCell> Function(Map<String, dynamic>) rowBuilder,
    List<QueryDocumentSnapshot> Function(List<QueryDocumentSnapshot>)? customSort,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 12),
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          FutureBuilder<QuerySnapshot>(
            future: query.get(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red));
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Text('No data available', style: TextStyle(color: Colors.white54));
              }

              final docs = customSort != null 
                  ? customSort(snapshot.data!.docs)
                  : snapshot.data!.docs;

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: MaterialStateProperty.all(Colors.black12),
                  columns: columns.map((c) => DataColumn(label: Text(c, style: TextStyle(color: color)))).toList(),
                  rows: docs.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return DataRow(cells: rowBuilder(data));
                  }).toList(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
