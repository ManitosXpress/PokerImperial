import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../user_detail_modal.dart';

// --- Models & Enums ---

enum ActivityType { financeIn, financeOut, game, security }

class ActivityEvent {
  final String id;
  final ActivityType type;
  final String message;
  final String detail;
  final double? amount;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;

  ActivityEvent({
    required this.id,
    required this.type,
    required this.message,
    required this.detail,
    this.amount,
    required this.timestamp,
    this.metadata,
  });

  factory ActivityEvent.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final typeStr = data['type'] as String? ?? 'NEW_USER';
    
    ActivityType type;
    switch (typeStr) {
      case 'DEPOSIT':
        type = ActivityType.financeIn;
        break;
      case 'WITHDRAWAL':
        type = ActivityType.financeOut;
        break;
      case 'GAME_BIG_WIN':
        type = ActivityType.game;
        break;
      case 'SECURITY_ALERT':
        type = ActivityType.security;
        break;
      default:
        type = ActivityType.game; // Default
    }

    final timestamp = (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
    final timeStr = DateFormat('HH:mm').format(timestamp);
    
    String detail = "$timeStr";
    if (data['metadata'] != null) {
        // Add more detail if available, e.g. method or table
        if (data['metadata']['reason'] != null) {
            detail += " • ${data['metadata']['reason']}";
        } else if (data['metadata']['tableId'] != null) {
            detail += " • Table: ${data['metadata']['tableId']}";
        }
    }

    return ActivityEvent(
      id: doc.id,
      type: type,
      message: data['message'] ?? 'Evento desconocido',
      detail: detail,
      amount: (data['amount'] as num?)?.toDouble(),
      timestamp: timestamp,
      metadata: data['metadata'],
    );
  }
}

// --- Widget ---

class LiveActivityFeed extends StatefulWidget {
  const LiveActivityFeed({super.key});

  @override
  State<LiveActivityFeed> createState() => _LiveActivityFeedState();
}

class _LiveActivityFeedState extends State<LiveActivityFeed> {
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  final List<ActivityEvent> _events = [];
  StreamSubscription? _subscription;
  bool _isFirstLoad = true;

  @override
  void initState() {
    super.initState();
    _setupFirestoreStream();
  }

  void _setupFirestoreStream() {
    _subscription = FirebaseFirestore.instance
        .collection('system_feed')
        .orderBy('timestamp', descending: true)
        .limit(20)
        .snapshots()
        .listen((snapshot) {
      
      if (_isFirstLoad) {
        // Initial load: just add all items without animation to avoid chaos
        _events.clear();
        for (var doc in snapshot.docs) {
          _events.add(ActivityEvent.fromFirestore(doc));
        }
        _isFirstLoad = false;
        if (mounted) setState(() {}); // Rebuild to show initial list
      } else {
        // Real-time updates: Handle new items
        for (var change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.added) {
            // Only add if it's newer than our newest item (to avoid re-adding old items if query shifts)
            // Or simply insert at 0 if it's a new document at the top
            if (change.newIndex == 0) {
                final newEvent = ActivityEvent.fromFirestore(change.doc);
                _insertEvent(newEvent);
            }
          }
        }
      }
    });
  }

  void _insertEvent(ActivityEvent event) {
    if (!mounted) return;
    
    _events.insert(0, event);
    _listKey.currentState?.insertItem(0, duration: const Duration(milliseconds: 500));
    
    // Keep list size manageable
    if (_events.length > 20) {
      final lastIndex = _events.length - 1;
      final removedItem = _events.removeAt(lastIndex);
      _listKey.currentState?.removeItem(
        lastIndex,
        (context, animation) => Container(), 
        duration: Duration.zero
      );
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // If first load and empty, show loading or empty state
    if (_isFirstLoad && _events.isEmpty) {
        // We can show a placeholder or just the container
    }

    return Container(
      margin: const EdgeInsets.all(24), // Margin from screen edges
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20.0),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1))),
                  color: Colors.white.withOpacity(0.02),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD700).withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.analytics_outlined, color: Color(0xFFFFD700), size: 24),
                    ),
                    const SizedBox(width: 16),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'LIVE ACTIVITY FEED',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            letterSpacing: 1.0,
                            fontFamily: 'Roboto', 
                          ),
                        ),
                        Text(
                          'Real-time platform events',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.green.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text('LIVE', style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              // List
              Expanded(
                child: _events.isEmpty && !_isFirstLoad 
                ? Center(child: Text("Esperando eventos...", style: TextStyle(color: Colors.white54)))
                : AnimatedList(
                  key: _listKey,
                  initialItemCount: _events.length,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemBuilder: (context, index, animation) {
                    // Safety check
                    if (index >= _events.length) return const SizedBox.shrink();
                    return _buildItem(context, _events[index], animation);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

    );
  }

  Future<void> _showUserDetail(String uid) async {
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: Color(0xFFFFD700))),
    );

    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      
      if (mounted) Navigator.pop(context); // Dismiss loading

      if (userDoc.exists && mounted) {
        showDialog(
          context: context,
          builder: (context) => UserDetailModal(
            uid: uid,
            userData: userDoc.data() as Map<String, dynamic>,
          ),
        );
      } else {
        if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Usuario no encontrado')),
            );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Dismiss loading
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al cargar usuario: $e')),
        );
      }
    }
  }

  Widget _buildItem(BuildContext context, ActivityEvent event, Animation<double> animation) {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, -0.5), // Slide down slightly
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutBack)),
      child: FadeTransition(
        opacity: animation,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: ListTile(
            onTap: () {
              if (event.metadata != null && event.metadata!['uid'] != null) {
                _showUserDetail(event.metadata!['uid']);
              }
            },
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: _buildLeadingIcon(event.type),
            title: Text(
              event.message,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 15,
                fontFamily: 'Roboto',
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(
                event.detail,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 13,
                ),
              ),
            ),
            trailing: _buildTrailing(event),
          ),
        ),
      ),
    );
  }

  Widget _buildLeadingIcon(ActivityType type) {
    IconData icon;
    Color color;

    switch (type) {
      case ActivityType.financeIn:
        icon = Icons.arrow_downward; // In
        color = Colors.greenAccent;
        break;
      case ActivityType.financeOut:
        icon = Icons.arrow_upward; // Out
        color = Colors.redAccent;
        break;
      case ActivityType.game:
        icon = Icons.videogame_asset;
        color = Colors.blueAccent;
        break;
      case ActivityType.security:
        icon = Icons.shield;
        color = Colors.orangeAccent;
        break;
    }

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.15),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 8,
            spreadRadius: 2,
          )
        ]
      ),
      child: Icon(icon, color: color, size: 24),
    );
  }

  Widget _buildTrailing(ActivityEvent event) {
    if (event.amount == null) return const SizedBox.shrink();

    Color color = Colors.white;
    String prefix = "";
    
    if (event.type == ActivityType.financeIn) {
      color = Colors.greenAccent;
      prefix = "+";
    } else if (event.type == ActivityType.financeOut) {
      color = Colors.redAccent;
      prefix = "-";
    } else if (event.type == ActivityType.game) {
      color = Colors.blueAccent;
      prefix = "";
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          "$prefix${event.amount!.toStringAsFixed(0)}",
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        if (event.type == ActivityType.financeIn || event.type == ActivityType.financeOut)
          Text(
            "USDT",
            style: TextStyle(
              color: color.withOpacity(0.7),
              fontSize: 10,
            ),
          ),
      ],
    );
  }
}
