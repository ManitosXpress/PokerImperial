import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/language_provider.dart';
import 'game/cash_tables_view.dart';
import 'tournament/tournament_list_screen.dart';
import '../widgets/create_table_dialog.dart';

class GameZoneScreen extends StatefulWidget {
  const GameZoneScreen({super.key});

  @override
  State<GameZoneScreen> createState() => _GameZoneScreenState();
}

class _GameZoneScreenState extends State<GameZoneScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _userRole;
  bool _isLoadingRole = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadUserRole();
  }

  Future<void> _loadUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      setState(() {
        _userRole = userDoc.data()?['role'] ?? 'player';
        _isLoadingRole = false;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);
    final isSpanish = languageProvider.currentLocale.languageCode == 'es';

    return Scaffold(
      backgroundColor: const Color(0xFF0a0e27),
      appBar: AppBar(
        title: Text(
          isSpanish ? 'Zona de Juego' : 'Game Zone',
          style: const TextStyle(
            color: Color(0xFFFFD700),
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.black,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFFFD700),
          labelColor: const Color(0xFFFFD700),
          unselectedLabelColor: Colors.white60,
          tabs: [
            Tab(
              icon: const Icon(Icons.table_chart),
              text: isSpanish ? 'Mesas Públicas' : 'Public Tables',
            ),
            Tab(
              icon: const Icon(Icons.emoji_events),
              text: isSpanish ? 'Torneos' : 'Tournaments',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          CashTablesView(userRole: _userRole),
          const TournamentListScreen(),
        ],
      ),
      floatingActionButton: _isLoadingRole || _userRole != 'club'
          ? null
          : FloatingActionButton.extended(
              onPressed: () {
                if (_tabController.index == 0) {
                  // Create Cash Table
                  showDialog(
                    context: context,
                    builder: (context) => const CreateTableDialog(),
                  );
                } else {
                  // Create Tournament
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(isSpanish
                          ? 'Crear Torneo - Próximamente'
                          : 'Create Tournament - Coming Soon'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
              },
              backgroundColor: const Color(0xFFFFD700),
              icon: const Icon(Icons.add, color: Colors.black),
              label: Text(
                _tabController.index == 0
                    ? (isSpanish ? 'Crear Mesa' : 'Create Table')
                    : (isSpanish ? 'Crear Torneo' : 'Create Tournament'),
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
    );
  }
}
