import 'package:flutter/material.dart';

class TournamentScopeCard extends StatelessWidget {
  final String scope;
  final bool isSelected;
  final VoidCallback onTap;

  const TournamentScopeCard({
    super.key,
    required this.scope,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isGlobal = scope == 'GLOBAL';
    
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  colors: isGlobal
                      ? [const Color(0xFF00D4FF), const Color(0xFF0099CC)]
                      : [const Color(0xFFFFD700), const Color(0xFFCC9900)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : LinearGradient(
                  colors: [Colors.white.withOpacity(0.05), Colors.white.withOpacity(0.02)],
                ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? (isGlobal ? const Color(0xFF00D4FF) : const Color(0xFFFFD700))
                : Colors.white.withOpacity(0.1),
            width: isSelected ? 3 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: (isGlobal ? const Color(0xFF00D4FF) : const Color(0xFFFFD700)).withOpacity(0.5),
                    blurRadius: 20,
                    spreadRadius: 2,
                  )
                ]
              : [],
        ),
        child: Column(
          children: [
            Icon(
              isGlobal ? Icons.public : Icons.shield,
              size: 48,
              color: isSelected
                  ? Colors.white
                  : Colors.white.withOpacity(0.3),
            ),
            const SizedBox(height: 12),
            Text(
              isGlobal ? '🌍 TORNEO GLOBAL' : '🏰 TORNEO DE CLUB',
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white.withOpacity(0.5),
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isGlobal
                  ? 'Abierto a todos los usuarios'
                  : 'Exclusivo para miembros del club',
              style: TextStyle(
                color: isSelected ? Colors.white70 : Colors.white.withOpacity(0.3),
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
