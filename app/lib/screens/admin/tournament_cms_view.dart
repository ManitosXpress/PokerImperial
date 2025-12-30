import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../widgets/imperial_currency.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../widgets/poker_loading_indicator.dart';
import '../../widgets/poker_loading_indicator.dart';
import '../game_screen.dart';
import '../tournament/create_tournament_screen.dart';
import '../tournament/tournament_lobby_screen.dart';

class TournamentCMSView extends StatefulWidget {
  const TournamentCMSView({super.key});

  @override
  State<TournamentCMSView> createState() => _TournamentCMSViewState();
}

class _TournamentCMSViewState extends State<TournamentCMSView> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
               builder: (context) => const CreateTournamentScreen(userRole: 'admin'),
            ),
          );
        },
        backgroundColor: Colors.amber,
        child: const Icon(Icons.add, color: Colors.black),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore.collection('tournaments')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
          if (!snapshot.hasData) return const Center(child: PokerLoadingIndicator(size: 40, color: Colors.amber));

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(child: Text('No hay torneos creados.', style: TextStyle(color: Colors.white54)));
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final tournamentId = docs[index].id;
              final status = (data['status'] ?? '').toString().toUpperCase();
              final showGodModeButton = status == 'RUNNING' || status == 'REGISTERING' || status == 'ACTIVE';
              
              // Determine status color
              Color statusColor = Colors.grey;
              if (status == 'RUNNING' || status == 'ACTIVE') statusColor = Colors.greenAccent;
              if (status == 'REGISTERING') statusColor = Colors.amberAccent;
              if (status == 'FINISHED') statusColor = Colors.redAccent;

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), // Reduced vertical margin
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withOpacity(0.08),
                      Colors.white.withOpacity(0.03),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: status == 'RUNNING' 
                        ? const Color(0xFF00FF88).withOpacity(0.3) 
                        : const Color(0xFFFFD700).withOpacity(0.3),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), // Reduced internal padding
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header: Icon + Name
                      Row(
                        children: [
                          const Icon(
                            Icons.emoji_events,
                            color: Color(0xFFFFD700),
                            size: 24, // Slightly smaller icon
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              data['name'] ?? 'Sin Nombre',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16, // Slightly smaller text
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10), // Reduced spacing
                      
                      // Info Badges Row 1: BuyIn + Type
                      Row(
                        children: [
                          _buildInfoChip(
                            Icons.attach_money,
                            'Buy-in',
                            ImperialCurrency(
                              amount: data['buyIn'], 
                              style: const TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.bold),
                              iconSize: 12,
                            ),
                            const Color(0xFFD4AF37),
                          ),
                          const SizedBox(width: 8),
                          _buildInfoChip(
                            Icons.category,
                            'Tipo',
                            Text(
                              data['type'] ?? 'Open',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
                            ),
                            Colors.blueAccent,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6), // Reduced spacing
                      
                      // Info Badges Row 2: Status
                       Row(
                        children: [
                          _buildInfoChip(
                            Icons.info_outline,
                            'Estado',
                            Text(
                              status,
                              style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 10),
                            ),
                            statusColor,
                          ),
                        ],
                      ),

                      const SizedBox(height: 12), // Reduced spacing
                      
                      // Action Button (Full Width)
                      if (showGodModeButton)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => TournamentLobbyScreen(
                                    tournamentId: tournamentId,
                                    isAdminMode: true,
                                  ),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00C851),
                              padding: const EdgeInsets.symmetric(vertical: 10), // Reduced vertical padding
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              elevation: 4,
                            ),
                            child: const Text(
                              'GESTIONAR',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14, // Slightly smaller font
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                        )
                      else
                        // Non-actionable state or view details
                         Container(
                           width: double.infinity,
                           padding: const EdgeInsets.symmetric(vertical: 8), // Reduced padding
                           decoration: BoxDecoration(
                             color: Colors.white.withOpacity(0.05),
                             borderRadius: BorderRadius.circular(10),
                           ),
                           alignment: Alignment.center,
                           child: Text(
                             'TORNEO ${status}',
                             style: const TextStyle(
                               color: Colors.white38,
                               fontWeight: FontWeight.bold,
                               letterSpacing: 1.0,
                               fontSize: 12,
                             ),
                           ),
                         ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
  Widget _buildInfoChip(IconData icon, String label, Widget content, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: TextStyle(
              color: color.withOpacity(0.8),
              fontSize: 10,
            ),
          ),
          content,
        ],
      ),
    );
  }
}


