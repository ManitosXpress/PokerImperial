import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/poker_loading_indicator.dart';
import 'user_management_view.dart';
import 'economy_view.dart';
import 'finance_history_view.dart';
import 'tournament_cms_view.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Super Admin Dashboard'),
        backgroundColor: Colors.black,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFFFD700),
          labelColor: const Color(0xFFFFD700),
          unselectedLabelColor: Colors.white54,
          tabs: const [
              Tab(icon: Icon(Icons.people), text: 'Usuarios'),
            Tab(icon: Icon(Icons.account_balance), text: 'Economía'),
            Tab(icon: Icon(Icons.history), text: 'Finanzas'),
            Tab(icon: Icon(Icons.emoji_events), text: 'Torneos'),
            Tab(icon: Icon(Icons.analytics), text: 'Live Feed'),
          ],
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/poker3_background.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        child: Container(
          color: Colors.black.withOpacity(0.8), // Dark overlay
          child: TabBarView(
            controller: _tabController,
            children: const [
              UserManagementView(),
              EconomyView(),
              FinanceHistoryView(),
              TournamentCMSView(),
              Center(child: Text('Live Feed (Coming Soon)', style: TextStyle(color: Colors.white))),
            ],
          ),
        ),
      ),
    );
  }
}
