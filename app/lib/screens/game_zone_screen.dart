import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/language_provider.dart';
import 'game/cash_tables_view.dart';
import 'tournament/tournament_list_screen.dart';
import '../widgets/create_table_dialog.dart';
import '../widgets/imperial_tab_bar.dart';

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
    _tabController.addListener(() {
      setState(() {}); // Rebuild to update FAB
    });
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
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF0a0e27),
              Colors.black,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Imperial Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'IMPERIAL LOBBY',
                      style: TextStyle(
                        color: Color(0xFFFFD700),
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                        shadows: [
                          Shadow(
                            color: Color(0xFFFFD700),
                            blurRadius: 20,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              // Imperial TabBar
              ImperialTabBar(
                controller: _tabController,
                tabs: [
                  ImperialTab(
                    icon: Icons.casino,
                    label: isSpanish ? 'Cash Games' : 'Cash Games',
                    activeColor: const Color(0xFF00FF88),
                  ),
                  ImperialTab(
                    icon: Icons.emoji_events,
                    label: isSpanish ? 'Torneos' : 'Tournaments',
                    activeColor: const Color(0xFFFFD700),
                  ),
                ],
              ),
              
              // Tab Content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    CashTablesView(userRole: _userRole),
                    const TournamentListScreen(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),

    );
  }
}
