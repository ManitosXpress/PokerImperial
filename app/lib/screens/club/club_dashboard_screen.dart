import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/club_provider.dart';
import 'create_club_screen.dart';
import '../../widgets/club_request_modal.dart';
import 'club_tournaments_screen.dart';
import 'club_leaderboard_screen.dart';
import 'tabs/live_tables_tab.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../widgets/poker_loading_indicator.dart';
import '../../widgets/club_owner_dashboard.dart';
import '../../widgets/seller_dashboard.dart';

class ClubDashboardScreen extends StatefulWidget {
  const ClubDashboardScreen({super.key});

  @override
  State<ClubDashboardScreen> createState() => _ClubDashboardScreenState();
}

class _ClubDashboardScreenState extends State<ClubDashboardScreen> {
  
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final provider = Provider.of<ClubProvider>(context, listen: false);
      await provider.fetchClubs();
      if (provider.myClub != null) {
        // We removed _fetchTotalMemberCredits, so this block might be empty or removed.
        // If we need to do something else, we can do it here.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final clubProvider = Provider.of<ClubProvider>(context);
    final myClub = clubProvider.myClub;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('CLUBS', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black.withOpacity(0.8), Colors.transparent],
            ),
          ),
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
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withOpacity(0.3),
                Colors.black.withOpacity(0.8),
              ],
            ),
          ),
          child: myClub != null
              ? _buildMyClubView(myClub)
              : _buildClubListView(clubProvider),
        ),
      ),
      floatingActionButton: myClub == null
          ? FloatingActionButton.extended(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => const ClubRequestModal(),
                );
              },
              label: const Text('CREAR CLUB', style: TextStyle(fontWeight: FontWeight.bold)),
              icon: const Icon(Icons.add),
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: Colors.black,
            )
          : null,
    );
  }

  Widget _buildMyClubView(Map<String, dynamic> club) {
    final clubProvider = Provider.of<ClubProvider>(context, listen: false);
    final role = clubProvider.currentUserRole;
    final bool isPlayer = role == 'player';
    
    // Define tabs based on role
    final List<Widget> tabs = [];
    final List<Widget> tabViews = [];
    
    // 1. Staff Tab (Only for non-players: Owners, Sellers)
    if (!isPlayer) {
      tabs.add(const Tab(text: 'STAFF'));
      tabViews.add(
        ClubLeaderboardScreen(
          clubId: club['id'],
          ownerId: club['ownerId'],
          isEmbedded: true,
          filter: LeaderboardFilter.staff,
        ),
      );
    }
    
    // 2. Jugadores Tab
    tabs.add(const Tab(text: 'JUGADORES'));
    tabViews.add(
      ClubLeaderboardScreen(
        clubId: club['id'],
        ownerId: club['ownerId'],
        isEmbedded: true,
        filter: LeaderboardFilter.players,
      ),
    );
    
    // 3. Mesas en Vivo Tab
    tabs.add(const Tab(text: 'MESAS EN VIVO'));
    tabViews.add(LiveTablesTab(clubId: club['id']));
    
    // 4. Torneos Tab
    tabs.add(const Tab(text: 'TORNEOS'));
    tabViews.add(
      ClubTournamentsScreen(
        clubId: club['id'],
        // Only show create button if role is explicitly 'club' (Owner)
        isOwner: role == 'club',
        isEmbedded: true,
      ),
    );

    return DefaultTabController(
      length: tabs.length,
      child: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverToBoxAdapter(
              child: Column(
                children: [
                  const SizedBox(height: 100), // AppBar spacer
                  // Club Header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFFFD700), width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFFD700).withOpacity(0.3),
                                blurRadius: 15,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: const CircleAvatar(
                            radius: 40,
                            backgroundColor: Color(0xFF1A1A2E),
                            child: Icon(Icons.shield, size: 40, color: Color(0xFFFFD700)),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          club['name'],
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 1.2,
                            shadows: [Shadow(color: Colors.black, blurRadius: 4, offset: Offset(0, 2))],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          club['description'],
                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Role-Based Dashboard (Executive Panel / Seller Panel)
                  Consumer<ClubProvider>(
                    builder: (context, provider, child) {
                      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
                      final role = provider.currentUserRole;
                      
                      // Owner (club role) sees Executive Panel
                      if (role == 'club' && club['ownerId'] == currentUserId) {
                        return ClubOwnerDashboard(
                          clubId: club['id'],
                          clubName: club['name'],
                        );
                      }
                      
                      // Seller sees Seller Panel
                      if (role == 'seller') {
                        return Column(
                          children: [
                            SellerDashboard(
                              clubId: club['id'],
                              clubName: club['name'],
                            ),
                            const SizedBox(height: 24),
                            _buildLeaveClubButton(context),
                          ],
                        );
                      }
                      
                      // Player sees no panel but can leave
                      if (role == 'player') {
                        return _buildLeaveClubButton(context);
                      }
                      
                      return const SizedBox.shrink();
                    },
                  ),
  
                  const SizedBox(height: 24),
                ],
              ),
            ),
            
            // Sticky TabBar
            SliverPersistentHeader(
              delegate: _SliverAppBarDelegate(
                TabBar(
                  isScrollable: true, // Make scrollable to fit tabs
                  indicator: BoxDecoration(
                    color: const Color(0xFFFFD700),
                    borderRadius: BorderRadius.circular(25),
                  ),
                  labelColor: Colors.black,
                  unselectedLabelColor: Colors.white60,
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                  tabs: tabs,
                ),
              ),
              pinned: true,
            ),
          ];
        },
        body: Container(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.5), // Darken background for list readability
          ),
          child: TabBarView(
            children: tabViews,
          ),
        ),
      ),
    );
  }

  Widget _buildClubListView(ClubProvider provider) {
    if (provider.isLoading) {
      return const Center(
        child: PokerLoadingIndicator(
          statusText: 'Loading Clubs...',
          color: Color(0xFFFFD700),
        ),
      );
    }

    if (provider.errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(provider.errorMessage!, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => provider.fetchClubs(),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD700), foregroundColor: Colors.black),
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
            Icon(Icons.search_off, color: Colors.white.withOpacity(0.3), size: 64),
            const SizedBox(height: 16),
            const Text(
              'No clubs found',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Create one to get started!',
              style: TextStyle(color: Colors.white54),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => provider.fetchClubs(),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD700), foregroundColor: Colors.black),
              child: const Text('Refresh'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: const Color(0xFFFFD700),
      backgroundColor: const Color(0xFF1A1A2E),
      onRefresh: () => provider.fetchClubs(),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 100, 16, 16), // Top padding for transparent AppBar
        itemCount: provider.clubs.length,
        itemBuilder: (context, index) {
          final club = provider.clubs[index];
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.white.withOpacity(0.1), Colors.white.withOpacity(0.05)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.amber.withOpacity(0.5)),
                ),
                child: const Icon(Icons.shield, color: Colors.amber),
              ),
              title: Text(
                club['name'],
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
              ),
              subtitle: Text(
                '${club['memberCount']} members',
                style: const TextStyle(color: Colors.white54),
              ),
              trailing: ElevatedButton(
                onPressed: () => _showJoinClubDialog(context, club['id'], club['name']),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: const Text('UNIRSE'),
              ),
            ),
          );
        },
      ),
    );
  }



  void _showJoinClubDialog(BuildContext context, String clubId, String clubName) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final clubProvider = Provider.of<ClubProvider>(context, listen: false);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Text('Unirse a $clubName', style: const TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '¡Únete a este Club!',
                style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 16),
              const Text(
                'Al unirte a este club, podrás participar inmediatamente en las mesas y torneos del club.',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              const Text(
                'Importante:',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'Una vez que te unas, tendrás acceso completo a todas las funcionalidades del club.',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context); // Close dialog
              
              try {
                // Join club directly
                await clubProvider.joinClub(clubId);
                
                // Show success message
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('✅ Te has unido al club exitosamente'),
                      backgroundColor: Colors.green,
                      duration: Duration(seconds: 3),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error al unirse al club: ${e.toString()}'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: Colors.black,
            ),
            child: const Text('Entrar al Club'),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaveClubButton(BuildContext context) {
    return Center(
      child: OutlinedButton.icon(
        onPressed: () => _showLeaveClubConfirmation(context),
        icon: const Icon(Icons.exit_to_app, color: Colors.red),
        label: const Text('SALIR DEL CLUB', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.black.withOpacity(0.4), // Dark background for visibility
          side: const BorderSide(color: Colors.red, width: 2),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
    );
  }

  void _showLeaveClubConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('¿Salir del Club?', style: TextStyle(color: Colors.white)),
        content: const Text(
          '¿Estás seguro de que deseas salir de este club? Perderás acceso a las mesas y torneos.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await Provider.of<ClubProvider>(context, listen: false).leaveClub();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Has salido del club exitosamente')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Salir'),
          ),
        ],
      ),
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar _tabBar;

  _SliverAppBarDelegate(this._tabBar);

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: const Color(0xFF1A1A2E), // Match background color
      child: _tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return false;
  }
}
