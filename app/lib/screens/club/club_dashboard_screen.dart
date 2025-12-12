import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/club_provider.dart';
import 'create_club_screen.dart';
import '../../widgets/club_request_modal.dart';
import 'club_tournaments_screen.dart';
import 'club_leaderboard_screen.dart';
import 'tabs/live_tables_tab.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../widgets/poker_loading_indicator.dart';
import '../../widgets/club_owner_dashboard.dart';
import '../../widgets/seller_dashboard.dart';

class ClubDashboardScreen extends StatefulWidget {
  const ClubDashboardScreen({super.key});

  @override
  State<ClubDashboardScreen> createState() => _ClubDashboardScreenState();
}

class _ClubDashboardScreenState extends State<ClubDashboardScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
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
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
    return NestedScrollView(
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
                      return SellerDashboard(
                        clubId: club['id'],
                        clubName: club['name'],
                      );
                    }
                    
                    // Player sees no panel
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
                controller: _tabController,
                isScrollable: true, // Make scrollable to fit 4 tabs
                indicator: BoxDecoration(
                  color: const Color(0xFFFFD700),
                  borderRadius: BorderRadius.circular(25),
                ),
                labelColor: Colors.black,
                unselectedLabelColor: Colors.white60,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                tabs: const [
                  Tab(text: 'STAFF'),
                  Tab(text: 'JUGADORES'),
                  Tab(text: 'MESAS EN VIVO'),
                  Tab(text: 'TORNEOS'),
                ],
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
          controller: _tabController,
          children: [
            // Staff Tab (Owner + Sellers)
            ClubLeaderboardScreen(
              clubId: club['id'],
              ownerId: club['ownerId'],
              isEmbedded: true,
              filter: LeaderboardFilter.staff,
            ),
            // Players Tab
            ClubLeaderboardScreen(
              clubId: club['id'],
              ownerId: club['ownerId'],
              isEmbedded: true,
              filter: LeaderboardFilter.players,
            ),
            // Live Tables Tab
            LiveTablesTab(clubId: club['id']),
            // Tournaments Tab
            ClubTournamentsScreen(
              clubId: club['id'],
              isOwner: club['ownerId'] == Provider.of<ClubProvider>(context, listen: false).myClub?['ownerId'],
              isEmbedded: true,
            ),
          ],
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

    // Get club details to obtain ownerId
    final clubProvider = Provider.of<ClubProvider>(context, listen: false);
    final club = clubProvider.clubs.firstWhere((c) => c['id'] == clubId, orElse: () => {});
    final ownerId = club['ownerId'] ?? 'N/A';

    final creditsController = TextEditingController();

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
                '¡Solicita unirte a este Club!',
                style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 16),
              const Text(
                'Al enviar esta solicitud, el administrador del club recibirá tu petición y podrá aprobarte.',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              const Text(
                'Importante:',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'Una vez aprobado, podrás participar en las mesas y torneos del club.',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: creditsController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Créditos a Cargar',
                  labelStyle: const TextStyle(color: Colors.white70),
                  hintText: 'Ej: 10000',
                  hintStyle: const TextStyle(color: Colors.white38),
                  enabledBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFFFFD700)),
                  ),
                  prefixIcon: const Icon(Icons.monetization_on, color: Color(0xFFFFD700)),
                  suffixText: 'créditos',
                  suffixStyle: const TextStyle(color: Color(0xFFFFD700)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              creditsController.dispose();
              Navigator.pop(context);
            },
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              final credits = creditsController.text.trim();
              if (credits.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Por favor ingresa la cantidad de créditos')),
                );
                return;
              }

              Navigator.pop(context); // Close dialog
              creditsController.dispose();
              
              // Generate the message
              final message = '''
🤝 Solicitud de Ingreso a Club

🏢 Datos del Club Destino
🆔 Club ID: $clubId
👑 Owner ID: $ownerId

👤 Datos del Solicitante
🆔 Usuario ID: ${user.uid}
📧 Email: ${user.email ?? 'No email'}
📱 Nombre: ${user.displayName ?? 'Sin nombre'}
💰 Créditos: $credits

This message was sent automatically with n8n''';

              final encodedMessage = Uri.encodeComponent(message);
              final urlString = 'http://t.me/AgenteBingobot?text=$encodedMessage';
              final url = Uri.parse(urlString);

              try {
                // Copy message to clipboard
                await Clipboard.setData(ClipboardData(text: message));
                
                // Open Telegram
                await launchUrl(url, mode: LaunchMode.externalApplication);
                
                // Show confirmation
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('✅ Mensaje copiado al portapapeles y enviado a Telegram'),
                      backgroundColor: Colors.green,
                      duration: Duration(seconds: 3),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('No se pudo abrir Telegram: $e')),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: Colors.black,
            ),
            child: const Text('Enviar Solicitud'),
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
