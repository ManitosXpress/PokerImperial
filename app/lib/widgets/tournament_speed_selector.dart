import 'package:flutter/material.dart';

class TournamentSpeedSelector extends StatelessWidget {
  final String selectedSpeed;
  final Function(String) onSpeedChanged;

  const TournamentSpeedSelector({
    super.key,
    required this.selectedSpeed,
    required this.onSpeedChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Velocidad del Torneo',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            _buildSpeedOption('TURBO', '⚡', 'Rápido'),
            const SizedBox(width: 12),
            _buildSpeedOption('REGULAR', '⏱️', 'Regular'),
            const SizedBox(width: 12),
            _buildSpeedOption('DEEP_STACK', '🏔️', 'Deep Stack'),
          ],
        ),
      ],
    );
  }

  Widget _buildSpeedOption(String speed, String emoji, String label) {
    final isSelected = selectedSpeed == speed;
    
    return Expanded(
      child: GestureDetector(
        onTap: () => onSpeedChanged(speed),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            gradient: isSelected
                ? const LinearGradient(
                    colors: [Color(0xFFE94560), Color(0xFFCC3850)],
                  )
                : null,
            color: isSelected ? null : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? const Color(0xFFE94560) : Colors.white.withOpacity(0.1),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Text(
                emoji,
                style: const TextStyle(fontSize: 24),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white.withOpacity(0.5),
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
