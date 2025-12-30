import 'dart:ui';
import 'package:flutter/material.dart';

// ==================== MOCK DATA CLASS ====================
class TournamentData {
  final String name;
  final double buyIn;
  final double fee;
  final String status; // 'registering' or 'playing'
  final int currentPlayers;
  final int maxPlayers;
  final int guaranteedPrize;
  final List<BlindLevel> blindStructure;
  final List<PayoutPlace> payouts;

  TournamentData({
    required this.name,
    required this.buyIn,
    required this.fee,
    required this.status,
    required this.currentPlayers,
    required this.maxPlayers,
    required this.guaranteedPrize,
    required this.blindStructure,
    required this.payouts,
  });

  // Mock data generator
  static TournamentData getMockData() {
    return TournamentData(
      name: 'Torneo Clásico Imperial',
      buyIn: 10.0,
      fee: 1.0,
      status: 'registering', // 'registering' or 'playing'
      currentPlayers: 45,
      maxPlayers: 100,
      guaranteedPrize: 1000,
      blindStructure: [
        BlindLevel(level: 1, smallBlind: 100, bigBlind: 200, ante: 0, duration: 10),
        BlindLevel(level: 2, smallBlind: 150, bigBlind: 300, ante: 0, duration: 10),
        BlindLevel(level: 3, smallBlind: 200, bigBlind: 400, ante: 50, duration: 10),
        BlindLevel(level: 4, smallBlind: 300, bigBlind: 600, ante: 75, duration: 10),
        BlindLevel(level: 5, smallBlind: 400, bigBlind: 800, ante: 100, duration: 10),
        BlindLevel(level: 6, smallBlind: 600, bigBlind: 1200, ante: 150, duration: 10),
        BlindLevel(level: 7, smallBlind: 800, bigBlind: 1600, ante: 200, duration: 10),
        BlindLevel(level: 8, smallBlind: 1000, bigBlind: 2000, ante: 250, duration: 10),
      ],
      payouts: [
        PayoutPlace(position: '1º Lugar', percentage: 50, amount: 500),
        PayoutPlace(position: '2º Lugar', percentage: 30, amount: 300),
        PayoutPlace(position: '3º Lugar', percentage: 20, amount: 200),
      ],
    );
  }
}

class BlindLevel {
  final int level;
  final int smallBlind;
  final int bigBlind;
  final int ante;
  final int duration; // minutes

  BlindLevel({
    required this.level,
    required this.smallBlind,
    required this.bigBlind,
    required this.ante,
    required this.duration,
  });
}

class PayoutPlace {
  final String position;
  final int percentage;
  final double amount;

  PayoutPlace({
    required this.position,
    required this.percentage,
    required this.amount,
  });
}

// ==================== MAIN WIDGET ====================
class TournamentDetailSheet extends StatelessWidget {
  final TournamentData tournament;

  const TournamentDetailSheet({
    Key? key,
    required this.tournament,
  }) : super(key: key);

  // Static method to show the sheet
  static void show(BuildContext context, {TournamentData? tournament}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TournamentDetailSheet(
        tournament: tournament ?? TournamentData.getMockData(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final isRegistering = tournament.status.toLowerCase() == 'registering';

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border.all(
                  color: Colors.amber.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    // ==================== HEADER ====================
                    _buildHeader(context, isRegistering),

                    // ==================== TABS ====================
                    _buildTabBar(),

                    // ==================== TAB CONTENT ====================
                    Expanded(
                      child: TabBarView(
                        children: [
                          _buildStructureTab(scrollController),
                          _buildPayoutsTab(scrollController),
                        ],
                      ),
                    ),

                    // ==================== FOOTER ====================
                    _buildFooter(context, isRegistering),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ==================== HEADER ====================
  Widget _buildHeader(BuildContext context, bool isRegistering) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.amber.withOpacity(0.2),
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Close button + Title Row
          Row(
            children: [
              Expanded(
                child: Text(
                  tournament.name,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              // Close button (X)
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: Colors.white70),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Buy-in subtitle
          Text(
            'Buy-in: \$${tournament.buyIn.toStringAsFixed(0)} + \$${tournament.fee.toStringAsFixed(0)} Fee',
            style: const TextStyle(
              fontSize: 16,
              color: Colors.white,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 12),

          // Status Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isRegistering ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isRegistering ? Colors.green : Colors.red,
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isRegistering ? Icons.how_to_reg : Icons.play_circle_filled,
                  color: isRegistering ? Colors.green : Colors.red,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  isRegistering ? 'REGISTRANDO' : 'EN JUEGO',
                  style: TextStyle(
                    color: isRegistering ? Colors.green : Colors.red,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== TAB BAR ====================
  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.amber.withOpacity(0.2),
            width: 1,
          ),
        ),
      ),
      child: TabBar(
        indicatorColor: Colors.amber,
        indicatorWeight: 3,
        labelColor: Colors.amber,
        unselectedLabelColor: Colors.white60,
        labelStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
        tabs: const [
          Tab(text: 'ESTRUCTURA'),
          Tab(text: 'PREMIOS'),
        ],
      ),
    );
  }

  // ==================== TAB 1: STRUCTURE (BLINDS) ====================
  Widget _buildStructureTab(ScrollController scrollController) {
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: tournament.blindStructure.length + 1, // +1 for header
      itemBuilder: (context, index) {
        if (index == 0) {
          // Table Header
          return _buildTableHeader();
        }

        final blind = tournament.blindStructure[index - 1];
        return _buildBlindRow(blind);
      },
    );
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _buildHeaderCell('Nivel', flex: 1),
          _buildHeaderCell('Ciegas', flex: 2),
          _buildHeaderCell('Ante', flex: 1),
          _buildHeaderCell('Tiempo', flex: 1),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(String text, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.amber,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildBlindRow(BlindLevel blind) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          _buildCell('${blind.level}', flex: 1),
          _buildCell('${blind.smallBlind}/${blind.bigBlind}', flex: 2),
          _buildCell('${blind.ante}', flex: 1),
          _buildCell('${blind.duration}m', flex: 1),
        ],
      ),
    );
  }

  Widget _buildCell(String text, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  // ==================== TAB 2: PAYOUTS ====================
  Widget _buildPayoutsTab(ScrollController scrollController) {
    final prizePool = tournament.currentPlayers * (tournament.buyIn + tournament.fee);
    final isGuaranteed = prizePool >= tournament.guaranteedPrize;
    final progressPercentage = (tournament.currentPlayers / tournament.maxPlayers).clamp(0.0, 1.0);

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        // Progress Bar
        _buildProgressBar(progressPercentage, isGuaranteed),
        const SizedBox(height: 24),

        // Payouts Header
        const Text(
          'Distribución de Premios',
          style: TextStyle(
            color: Colors.amber,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),

        // Payouts List
        ...tournament.payouts.map((payout) => _buildPayoutRow(payout)).toList(),
      ],
    );
  }

  Widget _buildProgressBar(double percentage, bool isGuaranteed) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Jugadores: ${tournament.currentPlayers}/${tournament.maxPlayers}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isGuaranteed ? Colors.green.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isGuaranteed ? Colors.green : Colors.orange,
                  width: 1,
                ),
              ),
              child: Text(
                isGuaranteed ? 'Garantizado Cubierto' : 'En Progreso',
                style: TextStyle(
                  color: isGuaranteed ? Colors.green : Colors.orange,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: percentage,
            minHeight: 20,
            backgroundColor: Colors.white.withOpacity(0.1),
            valueColor: AlwaysStoppedAnimation<Color>(
              isGuaranteed ? Colors.green : Colors.amber,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPayoutRow(PayoutPlace payout) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.amber.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // Position
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.amber.shade700, Colors.amber.shade400],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                payout.position.split('º')[0],
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  payout.position,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${payout.percentage}% del pozo',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),

          // Amount
          Text(
            '\$${payout.amount.toStringAsFixed(0)}',
            style: const TextStyle(
              color: Colors.amber,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== FOOTER ====================
  Widget _buildFooter(BuildContext context, bool isRegistering) {
    return const SizedBox.shrink();
  }
}
