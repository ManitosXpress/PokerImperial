import 'package:flutter/material.dart';
import '../services/admin_analytics_service.dart';
import '../widgets/admin/economy_kpi_card.dart';
import '../widgets/admin/liquidity_rake_chart.dart';
import '../widgets/admin/mint_burn_chart.dart';
import '../widgets/admin/top_users_table.dart';
import 'package:intl/intl.dart';

/// Enhanced Super Admin Economy Dashboard
/// 
/// Economic Intelligence Center with:
/// - Current liquidity and total rake (existing)
/// - 3 new KPI cards (24h betting volume, velocity, GGR)
/// - Line chart: 7-day liquidity vs rake trends
/// - Bar chart: Mint vs burn comparison
/// - Whales table: Top 10 holders
/// - Sharks table: Top 10 winners (24h)
class AdminEconomyDashboard extends StatefulWidget {
  const AdminEconomyDashboard({Key? key}) : super(key: key);

  @override
  State<AdminEconomyDashboard> createState() => _AdminEconomyDashboardState();
}

class _AdminEconomyDashboardState extends State<AdminEconomyDashboard> {
  final AdminAnalyticsService _analyticsService = AdminAnalyticsService();
  
  // Loading states
  bool _isLoadingMetrics = true;
  bool _isLoadingTrends = true;
  bool _isLoadingWhales = true;
  bool _isLoadingSharks = true;
  
  // Data
  double _totalLiquidity = 0;
  double _totalRake = 0;
  Metrics24h _metrics24h = Metrics24h.empty();
  List<DailyTrend> _weeklyTrends = [];
  List<UserRankingModel> _whales = [];
  List<UserRankingModel> _sharks = [];

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    await Future.wait([
      _loadLiquidityAndRake(),
      _load24hMetrics(),
      _loadWeeklyTrends(),
      _loadTopUsers(),
    ]);
  }

  Future<void> _loadLiquidityAndRake() async {
    try {
      final liquidity = await _analyticsService.getCurrentLiquidity();
      final rake = await _analyticsService.getTotalRake();
      
      setState(() {
        _totalLiquidity = liquidity;
        _totalRake = rake;
      });
    } catch (e) {
      print('Error loading liquidity/rake: $e');
    }
  }

  Future<void> _load24hMetrics() async {
    setState(() => _isLoadingMetrics = true);
    
    try {
      final metrics = await _analyticsService.get24hMetrics();
      
      setState(() {
        _metrics24h = metrics;
        _isLoadingMetrics = false;
      });
    } catch (e) {
      print('Error loading 24h metrics: $e');
      setState(() => _isLoadingMetrics = false);
    }
  }

  Future<void> _loadWeeklyTrends() async {
    setState(() => _isLoadingTrends = true);
    
    try {
      final trends = await _analyticsService.getWeeklyTrends(days: 7);
      
      setState(() {
        _weeklyTrends = trends;
        _isLoadingTrends = false;
      });
    } catch (e) {
      print('Error loading weekly trends: $e');
      setState(() => _isLoadingTrends = false);
    }
  }

  Future<void> _loadTopUsers() async {
    setState(() {
      _isLoadingWhales = true;
      _isLoadingSharks = true;
    });
    
    try {
      final whales = await _analyticsService.getTopHolders(limit: 10);
      
      setState(() {
        _whales = whales;
        _isLoadingWhales = false;
      });
    } catch (e) {
      print('Error loading whales: $e');
      setState(() => _isLoadingWhales = false);
    }
    
    try {
      final sharks = await _analyticsService.getTopWinners24h(limit: 10);
      
      setState(() {
        _sharks = sharks;
        _isLoadingSharks = false;
      });
    } catch (e) {
      print('Error loading sharks: $e');
      setState(() => _isLoadingSharks = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat('#,##0', 'en_US');
    
    return Scaffold(
      backgroundColor: const Color(0xFF0F1419),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1F2E),
        title: const Text('Economic Intelligence Center'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAllData,
            tooltip: 'Refresh Data',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadAllData,
        color: const Color(0xFF00FFC3),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ========================
              // EXISTING CARDS (Top Row)
              // ========================
              Row(
                children: [
                  // Total Liquidity Card
                  Expanded(
                    child: _buildMainMetricCard(
                      icon: Icons.water_drop,
                      label: 'Total Liquidity',
                      value: '\$${formatter.format(_totalLiquidity)}',
                      color: const Color(0xFF00A8FF),
                    ),
                  ),
                  const SizedBox(width: 16),
                  
                  // Total Rake Card
                  Expanded(
                    child: _buildMainMetricCard(
                      icon: Icons.casino,
                      label: 'Ganancias Casa (Rake)',
                      value: '\$${formatter.format(_totalRake)}',
                      color: const Color(0xFF00FFC3),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              
              // ========================
              // NEW KPI CARDS (3 Columns)
              // ========================
              if (_isLoadingMetrics)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator(
                      color: Color(0xFF00FFC3),
                    ),
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: EconomyKPICard(
                        icon: Icons.trending_up,
                        label: 'Volumen de Apuestas (24h)',
                        value: _metrics24h.bettingVolume,
                        iconColor: const Color(0xFFFFD700),
                        isCurrency: true,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: EconomyKPICard(
                        icon: Icons.speed,
                        label: 'Velocidad del Dinero',
                        value: _metrics24h.moneyVelocity.toDouble(),
                        iconColor: const Color(0xFF00A8FF),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: EconomyKPICard(
                        icon: Icons.local_fire_department,
                        label: 'GGR (24h)',
                        value: _metrics24h.ggr,
                        iconColor: const Color(0xFFFF4081),
                        isCurrency: true,
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 32),
              
              // ========================
              // CHARTS SECTION
              // ========================
              const Text(
                'Análisis de Tendencias',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              
              if (_isLoadingTrends)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator(
                      color: Color(0xFF00FFC3),
                    ),
                  ),
                )
              else if (_weeklyTrends.isEmpty)
                Container(
                  padding: const EdgeInsets.all(40),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1F2E),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Center(
                    child: Text(
                      'No hay datos de tendencias. Ejecuta el cron job para generar datos históricos.',
                      style: TextStyle(color: Colors.white60),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else
                Column(
                  children: [
                    // Liquidity vs Rake Line Chart
                    LiquidityRakeChart(trends: _weeklyTrends),
                    const SizedBox(height: 24),
                    
                    // Mint vs Burn Bar Chart
                    MintBurnChart(trends: _weeklyTrends),
                  ],
                ),
              const SizedBox(height: 32),
              
              // ========================
              // TOP USERS TABLES
              // ========================
              const Text(
                'Detección de Anomalías',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Whales Table
                  Expanded(
                    child: TopUsersTable(
                      title: 'The Whales 🐋',
                      icon: Icons.account_balance_wallet,
                      accentColor: const Color(0xFF00A8FF),
                      users: _whales,
                      type: RankingType.holder,
                      isLoading: _isLoadingWhales,
                    ),
                  ),
                  const SizedBox(width: 24),
                  
                  // Sharks Table
                  Expanded(
                    child: TopUsersTable(
                      title: 'The Sharks 🦈',
                      icon: Icons.emoji_events,
                      accentColor: const Color(0xFFFFD700),
                      users: _sharks,
                      type: RankingType.winner,
                      isLoading: _isLoadingSharks,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              
              // ========================
              // BANCO CENTRAL (Existing section)
              // ========================
              _buildBancoCentralSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainMetricCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 32),
          ),
          const SizedBox(height: 16),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBancoCentralSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF00FFC3).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Banco Central: Emisión de Moneda',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Aumenta el circulante total. Use con precaución.',
            style: TextStyle(
              color: Colors.white60,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 24),
          
          // Mint/Burn buttons and inputs (your existing implementation)
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    // Your existing mint logic
                  },
                  icon: const Icon(Icons.add_circle),
                  label: const Text('INYECTAR (MINT)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFD700),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    // Your existing burn logic
                  },
                  icon: const Icon(Icons.remove_circle),
                  label: const Text('RETIRAR (BURN)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF4081),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
