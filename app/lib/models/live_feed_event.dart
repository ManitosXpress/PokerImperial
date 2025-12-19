import 'package:cloud_firestore/cloud_firestore.dart';

enum LiveFeedEventType {
  bigWin,
  hugePot,
  tournamentStart,
  tournamentWin,
  royalFlush,
  fourOfAKind,
  unknown,
}

class LiveFeedEvent {
  final String eventId;
  final LiveFeedEventType type;
  final String playerName;
  final double? amount;
  final String? tableId;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;

  LiveFeedEvent({
    required this.eventId,
    required this.type,
    required this.playerName,
    this.amount,
    this.tableId,
    required this.timestamp,
    this.metadata,
  });

  factory LiveFeedEvent.fromJson(String id, Map<String, dynamic> json) {
    return LiveFeedEvent(
      eventId: id,
      type: _parseEventType(json['type'] as String?),
      playerName: json['playerName'] as String? ?? 'Unknown Player',
      amount: (json['amount'] as num?)?.toDouble(),
      tableId: json['tableId'] as String?,
      timestamp: (json['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  static LiveFeedEventType _parseEventType(String? typeStr) {
    switch (typeStr?.toLowerCase()) {
      case 'big_win':
      case 'bigwin':
        return LiveFeedEventType.bigWin;
      case 'huge_pot':
      case 'hugepot':
        return LiveFeedEventType.hugePot;
      case 'tournament_start':
      case 'tournamentstart':
        return LiveFeedEventType.tournamentStart;
      case 'tournament_win':
      case 'tournamentwin':
        return LiveFeedEventType.tournamentWin;
      case 'royal_flush':
      case 'royalflush':
        return LiveFeedEventType.royalFlush;
      case 'four_of_a_kind':
      case 'fourofakind':
        return LiveFeedEventType.fourOfAKind;
      default:
        return LiveFeedEventType.unknown;
    }
  }

  String get icon {
    switch (type) {
      case LiveFeedEventType.bigWin:
        return '🏆';
      case LiveFeedEventType.hugePot:
        return '💰';
      case LiveFeedEventType.tournamentStart:
        return '🎯';
      case LiveFeedEventType.tournamentWin:
        return '👑';
      case LiveFeedEventType.royalFlush:
        return '♠️';
      case LiveFeedEventType.fourOfAKind:
        return '🎲';
      default:
        return '🃏';
    }
  }

  bool get isHighValue => (amount ?? 0) > 1000;

  String getTimeAgo() {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inSeconds < 60) {
      return 'Justo ahora';
    } else if (difference.inMinutes < 60) {
      return 'Hace ${difference.inMinutes}m';
    } else if (difference.inHours < 24) {
      return 'Hace ${difference.inHours}h';
    } else {
      return 'Hace ${difference.inDays}d';
    }
  }

  String getDisplayText() {
    if (amount != null && amount! > 0) {
      return '$playerName ganó \$${amount!.toStringAsFixed(0)}';
    }
    return playerName;
  }
}
