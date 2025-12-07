import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/club_provider.dart';
import '../../widgets/poker_loading_indicator.dart';

/// Filter type for the leaderboard
enum LeaderboardFilter { all, staff, players }

class ClubLeaderboardScreen extends StatefulWidget {
  final String clubId;
  final String ownerId;
  final bool isEmbedded;
  /// Filter to apply: 'staff' (owner+sellers), 'players' (players only), or null (all)
  final LeaderboardFilter filter;

  const ClubLeaderboardScreen({
    super.key,
    required this.clubId,
    required this.ownerId,
    this.isEmbedded = false,
    this.filter = LeaderboardFilter.all,
  });

  @override
  State<ClubLeaderboardScreen> createState() => _ClubLeaderboardScreenState();
}

class _ClubLeaderboardScreenState extends State<ClubLeaderboardScreen> {
  List<Map<String, dynamic>> _leaderboard = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadLeaderboard();
  }

  Future<void> _loadLeaderboard() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final leaderboard = await Provider.of<ClubProvider>(context, listen: false)
          .fetchClubLeaderboard(widget.clubId);
      if (mounted) {
        setState(() {
          _leaderboard = leaderboard;
          
          // Apply role filter based on widget.filter
          if (widget.filter == LeaderboardFilter.staff) {
            // Staff: show only owner (club) and sellers
            _leaderboard = _leaderboard.where((user) {
              final role = user['role'] ?? 'player';
              return role == 'club' || role == 'seller' || user['uid'] == widget.ownerId;
            }).toList();
          } else if (widget.filter == LeaderboardFilter.players) {
            // Players: show only player role
            _leaderboard = _leaderboard.where((user) {
              final role = user['role'] ?? 'player';
              return role == 'player' && user['uid'] != widget.ownerId;
            }).toList();
          }
          
          // Sort: Owner -> Seller -> Player
          _leaderboard.sort((a, b) {
            if (a['uid'] == widget.ownerId) return -1;
            if (b['uid'] == widget.ownerId) return 1;
            
            final roleA = a['role'] ?? 'player';
            final roleB = b['role'] ?? 'player';
            
            if (roleA == 'seller' && roleB != 'seller') return -1;
            if (roleB == 'seller' && roleA != 'seller') return 1;
            
            return 0;
          });
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isEmbedded) {
      return _buildContent();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Club Leaderboard'),
        backgroundColor: const Color(0xFF1A1A2E),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadLeaderboard,
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
          ),
        ),
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: PokerLoadingIndicator(
          statusText: 'Loading Leaderboard...',
          color: Color(0xFFFFD700),
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 64),
              const SizedBox(height: 16),
              const Text(
                'Error loading leaderboard',
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadLeaderboard,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE94560),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Note: If you see a Firestore index error, check the Firebase Console for a link to create the required index.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (_leaderboard.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.people_outline, size: 64, color: Colors.white24),
            const SizedBox(height: 16),
            const Text(
              'No members yet',
              style: TextStyle(color: Colors.white54, fontSize: 18),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadLeaderboard,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _leaderboard.length,
      itemBuilder: (context, index) {
        final user = _leaderboard[index];
        final isTop3 = index < 3;
        final isOwner = user['uid'] == widget.ownerId;
        final role = user['role'] ?? 'player';
        final isSeller = role == 'seller';

        return Card(
          color: isOwner
              ? const Color(0xFFFFD700).withOpacity(0.2) // Gold for owner
              : isSeller
                  ? const Color(0xFF0088cc).withOpacity(0.2) // Blue for seller
                  : isTop3
                      ? const Color(0xFFE94560).withOpacity(0.2)
                      : Colors.white.withOpacity(0.05),
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: isOwner
                ? const BorderSide(color: Color(0xFFFFD700), width: 2)
                : isSeller
                    ? const BorderSide(color: Color(0xFF0088cc), width: 1)
                    : BorderSide.none,
          ),
          child: ListTile(
            leading: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  backgroundColor: isTop3 ? Colors.amber : Colors.grey,
                  child: Text(
                    '#${index + 1}',
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (isOwner) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.star, color: Color(0xFFFFD700), size: 24),
                ],
                if (isSeller) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.store, color: Color(0xFF0088cc), size: 24),
                ],
              ],
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    user['displayName'],
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: isOwner ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
                if (isOwner)
                  _buildRoleBadge('OWNER', const Color(0xFFFFD700)),
                if (isSeller)
                  _buildRoleBadge('SELLER', const Color(0xFF0088cc)),
              ],
            ),
            trailing: Text(
              '${user['credits']} pts',
              style: const TextStyle(
                color: Colors.amber,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRoleBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      margin: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
