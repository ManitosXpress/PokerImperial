import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/club_provider.dart';
import 'create_club_screen.dart';
import 'club_tournaments_screen.dart';
import 'club_leaderboard_screen.dart';

class ClubDashboardScreen extends StatefulWidget {
  const ClubDashboardScreen({super.key});

  @override
  State<ClubDashboardScreen> createState() => _ClubDashboardScreenState();
}

class _ClubDashboardScreenState extends State<ClubDashboardScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => 
      Provider.of<ClubProvider>(context, listen: false).fetchClubs()
    );
  }

  @override
  Widget build(BuildContext context) {
    final clubProvider = Provider.of<ClubProvider>(context);
    final myClub = clubProvider.myClub;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clubs'),
        backgroundColor: const Color(0xFF1A1A2E),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
          ),
        ),
        child: myClub != null
            ? _buildMyClubView(myClub)
            : _buildClubListView(clubProvider),
      ),
      floatingActionButton: myClub == null
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CreateClubScreen()),
                );
              },
              label: const Text('Create Club'),
              icon: const Icon(Icons.add),
              backgroundColor: const Color(0xFFE94560),
            )
          : null,
    );
  }

  Widget _buildMyClubView(Map<String, dynamic> club) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.shield, size: 80, color: Color(0xFFE94560)),
          const SizedBox(height: 20),
          Text(
            club['name'],
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            club['description'],
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 30),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                const Text(
                  'Club Wallet',
                  style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Text(
                  '${club['walletBalance'] ?? 0} Credits',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildActionButton(
                icon: Icons.emoji_events,
                label: 'Tournaments',
                onTap: () {
                  Navigator.push(
                    context, // Use context from build method, not passed
                    MaterialPageRoute(
                      builder: (_) => ClubTournamentsScreen(
                        clubId: club['id'],
                        isOwner: club['ownerId'] == Provider.of<ClubProvider>(context, listen: false).myClub?['ownerId'], // Check ownership
                      ),
                    ),
                  );
                },
              ),
              _buildActionButton(
                icon: Icons.leaderboard,
                label: 'Leaderboard',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ClubLeaderboardScreen(
                        clubId: club['id'],
                        ownerId: club['ownerId'],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 30),
          // Wallet Management (Owner Only)
          Consumer<ClubProvider>(
            builder: (context, provider, child) {
              final currentUserId = Provider.of<ClubProvider>(context, listen: false).myClub?['ownerId'];
              final isOwner = club['ownerId'] == currentUserId;
              
              if (!isOwner) return const SizedBox.shrink();
              
              return Column(
                children: [
                  const Text(
                    'Owner Controls',
                    style: TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () {
                      // TODO: Show wallet management dialog
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Wallet management coming soon!')),
                      );
                    },
                    icon: const Icon(Icons.account_balance_wallet),
                    label: const Text('Manage Club Wallet'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFD700),
                      foregroundColor: Colors.black,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 120,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFE94560).withOpacity(0.2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE94560).withOpacity(0.5)),
        ),
        child: Column(
          children: [
            Icon(icon, color: const Color(0xFFE94560), size: 32),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClubListView(ClubProvider provider) {
    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(
              'Error loading clubs',
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              provider.errorMessage!,
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => provider.fetchClubs(),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (provider.clubs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off, color: Colors.white54, size: 48),
            const SizedBox(height: 16),
            const Text(
              'No clubs found',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
            const SizedBox(height: 8),
            const Text(
              'Create one to get started!',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => provider.fetchClubs(),
              child: const Text('Refresh'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => provider.fetchClubs(),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: provider.clubs.length,
        itemBuilder: (context, index) {
          final club = provider.clubs[index];
          return Card(
            color: Colors.white.withOpacity(0.05),
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: const Icon(Icons.shield, color: Colors.amber),
              title: Text(
                club['name'],
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                '${club['memberCount']} members',
                style: const TextStyle(color: Colors.white70),
              ),
              trailing: ElevatedButton(
                onPressed: () => provider.joinClub(club['id']),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                ),
                child: const Text('Join'),
              ),
            ),
          );
        },
      ),
    );
  }
}
