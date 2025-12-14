import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/admin_analytics_service.dart';

/// Reusable table widget for displaying top users (whales/sharks)
/// 
/// Shows:
/// - Rank
/// - User avatar and name
/// - Value (balance for holders, profit for winners)
/// - Additional stats for winners (win rate, hands played)
/// - Collapsible to show top 3 by default
class TopUsersTable extends StatefulWidget {
  final String title;
  final IconData icon;
  final Color accentColor;
  final List<UserRankingModel> users;
  final RankingType type;
  final bool isLoading;

  const TopUsersTable({
    Key? key,
    required this.title,
    required this.icon,
    required this.accentColor,
    required this.users,
    required this.type,
    this.isLoading = false,
  }) : super(key: key);

  @override
  State<TopUsersTable> createState() => _TopUsersTableState();
}

class _TopUsersTableState extends State<TopUsersTable> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    // Determine how many users to show
    final displayedUsers = _isExpanded 
        ? widget.users 
        : widget.users.take(3).toList();
    
    final hasMore = widget.users.length > 3;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.accentColor.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Title
          Row(
            children: [
              Icon(
                widget.icon,
                color: widget.accentColor,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              // Compact expand/collapse button
              if (hasMore && !widget.isLoading && widget.users.isNotEmpty)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => setState(() => _isExpanded = !_isExpanded),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: widget.accentColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: widget.accentColor.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _isExpanded ? 'Ver menos' : 'Ver todos',
                            style: TextStyle(
                              color: widget.accentColor,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            _isExpanded ? Icons.expand_less : Icons.expand_more,
                            color: widget.accentColor,
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          
          // Loading state
          if (widget.isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(
                  color: Color(0xFF00FFC3),
                ),
              ),
            )
          else if (widget.users.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Text(
                  'No data available',
                  style: TextStyle(color: Colors.white60),
                ),
              ),
            )
          else
            // Table with animation
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: _buildTable(displayedUsers),
            ),
        ],
      ),
    );
  }

  Widget _buildTable(List<UserRankingModel> displayedUsers) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header
        _buildTableHeader(),
        const SizedBox(height: 12),
        
        // Rows with constrained height for scrolling when expanded
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: _isExpanded ? 500 : double.infinity,
          ),
          child: SingleChildScrollView(
            physics: _isExpanded 
                ? const AlwaysScrollableScrollPhysics() 
                : const NeverScrollableScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: displayedUsers.map((user) => _buildTableRow(user)).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 40,
            child: Text(
              'RANK',
              style: TextStyle(
                color: Colors.white60,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Expanded(
            flex: 3,
            child: Text(
              'USER',
              style: TextStyle(
                color: Colors.white60,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.right,
              ),
            ),
            const SizedBox(
              width: 70,
              child: Text(
                'HANDS',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTableRow(UserRankingModel user) {
    final formatter = NumberFormat('#,##0', 'en_US');
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.white.withOpacity(0.05),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // Rank with medal icon for top 3
          SizedBox(
            width: 40,
            child: _buildRankBadge(user.rank),
          ),
          
          // User avatar and name
          Expanded(
            flex: 3,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundImage: user.photoURL.isNotEmpty
                      ? NetworkImage(user.photoURL)
                      : null,
                  backgroundColor: widget.accentColor.withOpacity(0.2),
                  child: user.photoURL.isEmpty
                      ? Icon(
                          Icons.person,
                          size: 16,
                          color: widget.accentColor,
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.displayName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (user.email.isNotEmpty)
                        Text(
                          user.email,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.4),
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Value (balance or profit)
          Expanded(
            flex: 2,
            child: Text(
              '\$${formatter.format(user.value)}',
              style: TextStyle(
                color: user.value >= 0 
                    ? const Color(0xFF00FFC3) 
                    : const Color(0xFFFF4081),
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.right,
            ),
          ),
          
          // Additional stats for winners
          if (widget.type == RankingType.winner) ...[
            SizedBox(
              width: 80,
              child: Text(
                '${user.winRate ?? "0"}%',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
                textAlign: TextAlign.right,
              ),
            ),
            SizedBox(
              width: 70,
              child: Text(
                '${user.handsPlayed ?? 0}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRankBadge(int rank) {
    if (rank <= 3) {
      // Medal icons for top 3
      final icons = [
        Icons.workspace_premium, // Gold
        Icons.workspace_premium, // Silver
        Icons.workspace_premium, // Bronze
      ];
      final colors = [
        const Color(0xFFFFD700), // Gold
        const Color(0xFFC0C0C0), // Silver
        const Color(0xFFCD7F32), // Bronze
      ];
      
      return Icon(
        icons[rank - 1],
        color: colors[rank - 1],
        size: 24,
      );
    } else {
      return Text(
        '#$rank',
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      );
    }
  }
}
