import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/live_feed_event.dart';
import 'live_feed_card.dart';
import 'live_feed_list.dart';

class LiveFeedTicker extends StatefulWidget {
  final Function(String tableId)? onEventTap;

  const LiveFeedTicker({
    super.key,
    this.onEventTap,
  });

  @override
  State<LiveFeedTicker> createState() => _LiveFeedTickerState();
}

class _LiveFeedTickerState extends State<LiveFeedTicker>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  bool _showNewIndicator = false;
  String? _lastEventId;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _showNewIndicator = false;
      }
    });
  }

  void _handleNewEvent(String eventId) {
    if (_lastEventId != null && _lastEventId != eventId && !_isExpanded) {
      setState(() {
        _showNewIndicator = true;
      });
      
      // Hide indicator after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && !_isExpanded) {
          setState(() {
            _showNewIndicator = false;
          });
        }
      });
    }
    _lastEventId = eventId;
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final expandedHeight = (screenHeight * 0.5).clamp(300.0, 500.0);

    return Stack(
      children: [
        // Backdrop when expanded
        if (_isExpanded)
          Positioned.fill(
            child: GestureDetector(
              onTap: _toggleExpanded,
              child: Container(
                color: Colors.black.withOpacity(0.3),
              ),
            ),
          ),

        // Main ticker container
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: GestureDetector(
            onTap: _isExpanded ? null : _toggleExpanded,
            onVerticalDragEnd: _isExpanded
                ? (details) {
                    if (details.primaryVelocity! > 300) {
                      _toggleExpanded();
                    }
                  }
                : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              height: _isExpanded ? expandedHeight : 60,
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF0a0e27).withOpacity(0.85),
                      border: Border(
                        top: BorderSide(
                          color: const Color(0xFF00FF88).withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                    ),
                    child: Column(
                      children: [
                        // Header/Collapsed View
                        _buildHeader(),

                        // Expanded content
                        if (_isExpanded)
                          Expanded(
                            child: LiveFeedList(
                              onEventTap: (tableId) {
                                _toggleExpanded();
                                widget.onEventTap?.call(tableId);
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('live_feed')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .snapshots(),
      builder: (context, snapshot) {
        LiveFeedEvent? latestEvent;
        
        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
          final doc = snapshot.data!.docs.first;
          latestEvent = LiveFeedEvent.fromJson(
            doc.id,
            doc.data() as Map<String, dynamic>,
          );
          
          // Track new events
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _handleNewEvent(latestEvent!.eventId);
          });
        }

        return Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              // New event indicator
              if (_showNewIndicator && !_isExpanded)
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    return Container(
                      width: 10,
                      height: 10,
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF00FF88),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00FF88).withOpacity(
                              0.8 * _pulseController.value,
                            ),
                            blurRadius: 10 * (1 + _pulseController.value),
                            spreadRadius: 2 * _pulseController.value,
                          ),
                        ],
                      ),
                    );
                  },
                ),

              // Live icon
              const Icon(
                Icons.play_circle_filled,
                color: Color(0xFF00FF88),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'LIVE',
                style: const TextStyle(
                  color: Color(0xFF00FF88),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(width: 16),

              // Latest event or placeholder
              Expanded(
                child: latestEvent != null
                    ? LiveFeedCard(
                        event: latestEvent,
                        isCompact: true,
                        onTap: _toggleExpanded,
                      )
                    : Text(
                        'Esperando actividad...',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 14,
                        ),
                      ),
              ),

              // Expand/collapse indicator
              AnimatedRotation(
                turns: _isExpanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 300),
                child: Icon(
                  Icons.keyboard_arrow_up,
                  color: Colors.white.withOpacity(0.6),
                  size: 24,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
