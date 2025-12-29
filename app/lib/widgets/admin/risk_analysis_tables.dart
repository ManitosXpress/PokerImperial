import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../imperial_currency.dart';

class RiskAnalysisTables extends StatelessWidget {
  const RiskAnalysisTables({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildTableSection(
          title: 'THE WHALES (TOP HOLDERS)',
          icon: Icons.account_balance_wallet,
          color: const Color(0xFFFFD700), // Gold
          query: FirebaseFirestore.instance.collection('users').orderBy('credit', descending: true).limit(10),
          columns: ['USUARIO', 'SALDO'],
          rowBuilder: (data) {
            return [
              DataCell(
                Row(
                  children: [
                     Container(
                       width: 32, height: 32,
                       alignment: Alignment.center,
                       decoration: BoxDecoration(
                         color: const Color(0xFFFFD700).withOpacity(0.1),
                         shape: BoxShape.circle,
                       ),
                       child: Text(
                         (data['displayName'] ?? 'U').toString().substring(0,1).toUpperCase(),
                         style: GoogleFonts.cinzel(color: const Color(0xFFFFD700), fontWeight: FontWeight.bold),
                       ),
                     ),
                     const SizedBox(width: 12),
                     Text(data['displayName'] ?? 'Unknown', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w500)),
                  ],
                )
              ),
              DataCell(ImperialCurrency(
                  amount: data['credit'] ?? 0, 
                  style: GoogleFonts.sourceCodePro(color: const Color(0xFFFFD700), fontWeight: FontWeight.bold, fontSize: 14), 
                  iconSize: 14
              )),
            ];
          },
        ),
        const SizedBox(height: 32),
        _buildTableSection(
          title: 'THE SHARKS (GANADORES 24H)',
          icon: Icons.trending_up,
          color: const Color(0xFF00FF88), // Neon Green
          query: FirebaseFirestore.instance.collection('financial_ledger')
              .where('type', isEqualTo: 'GAME_WIN')
              .limit(500),
          columns: ['USUARIO', 'GANANCIA', 'MESA'],
          rowBuilder: (data) {
            return [
              DataCell(Text(data['userName'] ?? data['userId'] ?? 'Unknown', style: GoogleFonts.outfit(color: Colors.white))),
              DataCell(Row(
                children: [
                  const Text('+', style: TextStyle(color: Color(0xFF00FF88), fontWeight: FontWeight.bold)),
                  ImperialCurrency(
                      amount: data['netProfit'] ?? 0, 
                      style: GoogleFonts.sourceCodePro(color: const Color(0xFF00FF88), fontWeight: FontWeight.bold, fontSize: 14), 
                      iconSize: 14
                  ),
                ],
              )),
              DataCell(
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Text(data['tableId'] ?? '-', style: GoogleFonts.outfit(color: Colors.white54, fontSize: 12)),
                )
              ),
            ];
          },
          customSort: (List<QueryDocumentSnapshot> docs) {
            final now = DateTime.now();
            final yesterday = now.subtract(const Duration(hours: 24));
            
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
            
            filtered.sort((a, b) {
              final dataA = a.data() as Map<String, dynamic>;
              final dataB = b.data() as Map<String, dynamic>;
              final profitA = (dataA['netProfit'] as num?)?.toDouble() ?? 0.0;
              final profitB = (dataB['netProfit'] as num?)?.toDouble() ?? 0.0;
              return profitB.compareTo(profitA);
            });
            
            return filtered.take(10).toList();
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
      width: double.infinity, // Force full width
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2C), // Dark Navy
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(bottom: BorderSide(color: color.withOpacity(0.1))),
            ),
            child: Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 16),
                Text(
                    title, 
                    style: GoogleFonts.outfit(
                        color: Colors.white, 
                        fontSize: 16, 
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5
                    )
                ),
              ],
            ),
          ),
          
          // Table
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: FutureBuilder<QuerySnapshot>(
              future: query.get(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text('Error loading data', style: TextStyle(color: Colors.redAccent)),
                  );
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Center(child: Text('No data available', style: TextStyle(color: Colors.white54))),
                  );
                }
            
                final docs = customSort != null 
                    ? customSort(snapshot.data!.docs)
                    : snapshot.data!.docs;
            
                return SizedBox(
                  width: double.infinity,
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      dividerColor: Colors.transparent, 
                      dataTableTheme: DataTableThemeData(
                        headingRowColor: MaterialStateProperty.all(Colors.transparent),
                        dataRowColor: MaterialStateProperty.resolveWith<Color?>((Set<MaterialState> states) {
                              if (states.contains(MaterialState.hovered)) return color.withOpacity(0.05);
                              return Colors.transparent;
                        }),
                      )
                    ),
                    child: DataTable(
                      horizontalMargin: 20,
                      columnSpacing: 20,
                      headingTextStyle: GoogleFonts.outfit(color: color.withOpacity(0.7), fontWeight: FontWeight.bold, letterSpacing: 1),
                      dataTextStyle: GoogleFonts.outfit(color: Colors.white70),
                      columns: columns.map((c) => DataColumn(label: Text(c))).toList(),
                      rows: docs.asMap().entries.map((entry) {
                         final index = entry.key;
                         final doc = entry.value;
                         final data = doc.data() as Map<String, dynamic>;
                         
                         // Alternate row background for subtlety? No, keep it clean.
                         return DataRow(
                           cells: rowBuilder(data),
                           color: MaterialStateProperty.resolveWith<Color?>((Set<MaterialState> states) {
                              if (index % 2 == 1) return Colors.white.withOpacity(0.02);
                              return null;
                           }),
                         );
                      }).toList(),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
