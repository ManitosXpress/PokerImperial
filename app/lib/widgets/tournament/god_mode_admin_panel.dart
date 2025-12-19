import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../imperial_currency.dart';
import '../../providers/tournament_provider.dart';

/// God Mode Admin UI Component
/// Displays admin controls and financial KPIs for tournament management
class GodModeAdminPanel extends StatelessWidget {
  final Map<String, dynamic> tournament;
  final String tournamentId;

  const GodModeAdminPanel({
    super.key,
    required this.tournament,
    required this.tournamentId,
  });

  @override
  Widget build(BuildContext context) {
    final status = tournament['status'] ?? '';
    final isRunning = status == 'RUNNING';
    final isPaused = tournament['isPaused'] ?? false;
    final currentBlindLevel = tournament['currentBlindLevel'] ?? 1;
    final totalRake = tournament['totalRakeCollected'] ?? 0;

    return Column(
      children: [
        // Financial KPIs (Only visible when running)
        if (isRunning) _buildFinancialKPIs(context),

        const SizedBox(height: 16),

        // Emergency Control Panel
        _buildEmergencyControls(context, isRunning, isPaused, currentBlindLevel),
      ],
    );
  }

  Widget _buildFinancialKPIs(BuildContext context) {
    final totalRake = tournament['totalRakeCollected'] ?? 0;
    final startedAt = tournament['startedAt'];
    
    // Calculate duration
    String duration = '--:--:--';
    if (startedAt != null) {
      final now = DateTime.now();
      final start = (startedAt as dynamic).toDate() as DateTime;
      final diff = now.difference(start);
      duration = '${diff.inHours.toString().padLeft(2, '0')}:${(diff.inMinutes % 60).toString().padLeft(2, '0')}:${(diff.inSeconds % 60).toString().padLeft(2, '0')}';
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.black.withOpacity(0.6),
            Colors.black.withOpacity(0.3),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD4AF37), width: 2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD4AF37).withOpacity(0.3),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildKPIChipWithWidget('💰', 'Rake Total', 
            ImperialCurrency(
              amount: totalRake,
              style: const TextStyle(
                color: Colors.green,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
              iconSize: 14,
            )
          ),
          _buildKPIChip('⏱️', 'Duración', duration, Colors.blue),
          _buildKPIChip('👁️', 'Estado', 'GOD MODE', const Color(0xFFB71C1C)),
        ],
      ),
    );
  }

  Widget _buildKPIChip(String emoji, String label, String value, Color color) {
    return _buildKPIChipWithWidget(emoji, label, Text(
      value,
      style: TextStyle(
        color: color,
        fontSize: 14,
        fontWeight: FontWeight.bold,
      ),
    ));
  }

  Widget _buildKPIChipWithWidget(String emoji, String label, Widget valueWidget) {
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 24)),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 10,
          ),
        ),
        valueWidget,
      ],
    );
  }

  Widget _buildEmergencyControls(
    BuildContext context,
    bool isRunning,
    bool isPaused,
    int currentBlindLevel,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFB71C1C).withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFB71C1C), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.admin_panel_settings, color: Color(0xFFD4AF37)),
              SizedBox(width: 8),
              Text(
                'PANEL DE CONTROL DE EMERGENCIA',
                style: TextStyle(
                  color: Color(0xFFD4AF37),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              // Pause/Resume Button
              if (isRunning)
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _handlePauseResume(context, isPaused),
                    icon: Icon(isPaused ? Icons.play_arrow : Icons.pause),
                    label: Text(isPaused ? 'REANUDAR' : 'PAUSAR'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isPaused ? Colors.green : Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              
              if (isRunning) const SizedBox(width: 8),
              
              // Force Blind Level Button
              if (isRunning)
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _handleForceBlindLevel(context, currentBlindLevel),
                    icon: const Icon(Icons.fast_forward),
                    label: Text('FORZAR (Lvl $currentBlindLevel)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF9C27B0),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // Broadcast Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _handleBroadcast(context),
              icon: const Icon(Icons.campaign),
              label: const Text('ANUNCIO GLOBAL'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1976D2),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handlePauseResume(BuildContext context, bool isPaused) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Text(
          isPaused ? '¿Reanudar Torneo?' : '¿Pausar Torneo?',
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          isPaused 
              ? 'Esto permitirá que el juego continúe en todas las mesas.' 
              : 'Esto congelará todas las mesas activas.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: isPaused ? Colors.green : Colors.orange,
            ),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        final provider = Provider.of<TournamentProvider>(context, listen: false);
        if (isPaused) {
          await provider.adminResumeTournament(tournamentId);
          _showSnackbar(context, '▶️ Torneo reanudado', Colors.green);
        } else {
          await provider.adminPauseTournament(tournamentId);
          _showSnackbar(context, '⏸️ Torneo pausado', Colors.orange);
        }
      } catch (e) {
        _showSnackbar(context, 'Error: $e', Colors.red);
      }
    }
  }

  void _handleForceBlindLevel(BuildContext context, int currentLevel) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('¿Forzar Nivel de Ciegas?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Esto incrementará el nivel de ciegas de $currentLevel a ${currentLevel + 1} inmediatamente.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF9C27B0)),
            child: const Text('Forzar'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        final provider = Provider.of<TournamentProvider>(context, listen: false);
        final result = await provider.adminForceBlindLevel(tournamentId);
        final newLevel = result['newLevel'];
        final smallBlind = result['smallBlind'];
        final bigBlind = result['bigBlind'];
        _showSnackbar(
          context,
          '⏩ Nivel forzado: $smallBlind/$bigBlind (Nivel $newLevel)',
          const Color(0xFF9C27B0),
        );
      } catch (e) {
        _showSnackbar(context, 'Error: $e', Colors.red);
      }
    }
  }

  void _handleBroadcast(BuildContext context) {
    final messageController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Anuncio Global', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: messageController,
          style: const TextStyle(color: Colors.white),
          maxLength: 500,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Escribe tu mensaje...',
            hintStyle: TextStyle(color: Colors.white30),
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              final message = messageController.text.trim();
              if (message.isEmpty) {
                Navigator.pop(ctx);
                return;
              }

              Navigator.pop(ctx); // Close dialog first

              try {
                final provider = Provider.of<TournamentProvider>(context, listen: false);
                await provider.adminBroadcastMessage(tournamentId, message);
                _showSnackbar(context, '📢 Anuncio enviado', Colors.blue);
              } catch (e) {
                _showSnackbar(context, 'Error: $e', Colors.red);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1976D2)),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
  }

  void _showSnackbar(BuildContext context, String message, Color color) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: color,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
}
