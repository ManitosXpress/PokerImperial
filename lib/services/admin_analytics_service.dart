import 'package:cloud_functions/cloud_functions.dart';

/// Service for fetching economic analytics data from Cloud Functions
class AdminAnalyticsService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  /// Get top holders (whales) - users with highest balance
  Future<List<UserRankingModel>> getTopHolders({int limit = 10}) async {
    try {
      final result = await _functions
          .httpsCallable('getTopHoldersFunction')
          .call({'limit': limit});

      if (result.data['success'] == true) {
        final List<dynamic> whales = result.data['whales'] ?? [];
        return whales
            .map((data) => UserRankingModel.fromMap(data, RankingType.holder))
            .toList();
      }

      return [];
    } catch (e) {
      print('Error fetching top holders: $e');
      rethrow;
    }
  }

  /// Get top winners in last 24h (sharks)
  Future<List<UserRankingModel>> getTopWinners24h({int limit = 10}) async {
    try {
      final result = await _functions
          .httpsCallable('getTopWinners24hFunction')
          .call({'limit': limit});

      if (result.data['success'] == true) {
        final List<dynamic> sharks = result.data['sharks'] ?? [];
        return sharks
            .map((data) => UserRankingModel.fromMap(data, RankingType.winner))
            .toList();
      }

      return [];
    } catch (e) {
      print('Error fetching top winners 24h: $e');
      rethrow;
    }
  }

  /// Get 24h real-time metrics
  Future<Metrics24h> get24hMetrics() async {
    try {
      final result =
          await _functions.httpsCallable('get24hMetricsFunction').call();

      if (result.data['success'] == true) {
        return Metrics24h.fromMap(result.data['metrics']);
      }

      return Metrics24h.empty();
    } catch (e) {
      print('Error fetching 24h metrics: $e');
      rethrow;
    }
  }

  /// Get weekly trends for charts (7 days)
  Future<List<DailyTrend>> getWeeklyTrends({int days = 7}) async {
    try {
      final result = await _functions
          .httpsCallable('getWeeklyTrendsFunction')
          .call({'days': days});

      if (result.data['success'] == true) {
        final List<dynamic> trends = result.data['trends'] ?? [];
        return trends.map((data) => DailyTrend.fromMap(data)).toList();
      }

      return [];
    } catch (e) {
      print('Error fetching weekly trends: $e');
      rethrow;
    }
  }

  /// Get current total liquidity
  Future<double> getCurrentLiquidity() async {
    try {
      final result =
          await _functions.httpsCallable('getCurrentLiquidityFunction').call();

      if (result.data['success'] == true) {
        return (result.data['totalLiquidity'] ?? 0).toDouble();
      }

      return 0.0;
    } catch (e) {
      print('Error fetching current liquidity: $e');
      rethrow;
    }
  }

  /// Get total rake collected all-time
  Future<double> getTotalRake() async {
    try {
      final result =
          await _functions.httpsCallable('getTotalRakeFunction').call();

      if (result.data['success'] == true) {
        return (result.data['totalRake'] ?? 0).toDouble();
      }

      return 0.0;
    } catch (e) {
      print('Error fetching total rake: $e');
      rethrow;
    }
  }
}

// ============================================================================
// DATA MODELS
// ============================================================================

enum RankingType { holder, winner }

/// Model for user rankings (whales and sharks)
class UserRankingModel {
  final String uid;
  final String displayName;
  final String email;
  final String photoURL;
  final int rank;
  final double value; // credit for holders, netProfit for winners
  final RankingType type;

  // Additional fields for winners
  final int? wins;
  final int? losses;
  final int? handsPlayed;
  final String? winRate;

  UserRankingModel({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.photoURL,
    required this.rank,
    required this.value,
    required this.type,
    this.wins,
    this.losses,
    this.handsPlayed,
    this.winRate,
  });

  factory UserRankingModel.fromMap(Map<String, dynamic> map, RankingType type) {
    return UserRankingModel(
      uid: map['uid'] ?? '',
      displayName: map['displayName'] ?? 'Unknown',
      email: map['email'] ?? '',
      photoURL: map['photoURL'] ?? '',
      rank: map['rank'] ?? 0,
      value: type == RankingType.holder
          ? (map['credit'] ?? 0).toDouble()
          : (map['netProfit'] ?? 0).toDouble(),
      type: type,
      wins: map['wins'],
      losses: map['losses'],
      handsPlayed: map['handsPlayed'],
      winRate: map['winRate'],
    );
  }
}

/// Model for 24h metrics
class Metrics24h {
  final double bettingVolume;
  final int handsPlayed;
  final double ggr; // Gross Gaming Revenue (rake)
  final int activeUsers;
  final int moneyVelocity;

  Metrics24h({
    required this.bettingVolume,
    required this.handsPlayed,
    required this.ggr,
    required this.activeUsers,
    required this.moneyVelocity,
  });

  factory Metrics24h.fromMap(Map<String, dynamic> map) {
    return Metrics24h(
      bettingVolume: (map['bettingVolume'] ?? 0).toDouble(),
      handsPlayed: map['handsPlayed'] ?? 0,
      ggr: (map['ggr'] ?? 0).toDouble(),
      activeUsers: map['activeUsers'] ?? 0,
      moneyVelocity: map['moneyVelocity'] ?? 0,
    );
  }

  factory Metrics24h.empty() {
    return Metrics24h(
      bettingVolume: 0,
      handsPlayed: 0,
      ggr: 0,
      activeUsers: 0,
      moneyVelocity: 0,
    );
  }
}

/// Model for daily trends (for charts)
class DailyTrend {
  final String date; // YYYY-MM-DD
  final double totalLiquidity;
  final double totalRake;
  final double totalMint;
  final double totalBurn;
  final double totalVolume;
  final int handsPlayed;
  final int activeUsers;
  final double netFlow;

  DailyTrend({
    required this.date,
    required this.totalLiquidity,
    required this.totalRake,
    required this.totalMint,
    required this.totalBurn,
    required this.totalVolume,
    required this.handsPlayed,
    required this.activeUsers,
    required this.netFlow,
  });

  factory DailyTrend.fromMap(Map<String, dynamic> map) {
    return DailyTrend(
      date: map['date'] ?? '',
      totalLiquidity: (map['totalLiquidity'] ?? 0).toDouble(),
      totalRake: (map['totalRake'] ?? 0).toDouble(),
      totalMint: (map['totalMint'] ?? 0).toDouble(),
      totalBurn: (map['totalBurn'] ?? 0).toDouble(),
      totalVolume: (map['totalVolume'] ?? 0).toDouble(),
      handsPlayed: map['handsPlayed'] ?? 0,
      activeUsers: map['activeUsers'] ?? 0,
      netFlow: (map['netFlow'] ?? 0).toDouble(),
    );
  }
}
