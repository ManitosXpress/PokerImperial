import 'package:flutter/material.dart';

enum BlindTier {
  micro(label: 'Micro', maxBigBlind: 20, color: Color(0xFF00FF88)),
  low(label: 'Low', maxBigBlind: 100, color: Color(0xFF00D4FF)),
  medium(label: 'Medium', maxBigBlind: 500, color: Color(0xFFFFD700)),
  high(label: 'High', maxBigBlind: 999999, color: Color(0xFFE94560));

  final String label;
  final int maxBigBlind;
  final Color color;

  const BlindTier({
    required this.label,
    required this.maxBigBlind,
    required this.color,
  });
}

class BlindFiltersChips extends StatefulWidget {
  final BlindTier? selectedTier;
  final Function(BlindTier?) onTierSelected;

  const BlindFiltersChips({
    super.key,
    this.selectedTier,
    required this.onTierSelected,
  });

  @override
  State<BlindFiltersChips> createState() => _BlindFiltersChipsState();
}

class _BlindFiltersChipsState extends State<BlindFiltersChips> {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'FILTRAR POR CIEGAS',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(
                  label: 'Todas',
                  isSelected: widget.selectedTier == null,
                  color: const Color(0xFFFFD700),
                  onTap: () => widget.onTierSelected(null),
                ),
                const SizedBox(width: 8),
                ...BlindTier.values.map((tier) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _FilterChip(
                      label: tier.label,
                      subtitle: tier == BlindTier.high
                          ? '>\$${BlindTier.medium.maxBigBlind}'
                          : '≤\$${tier.maxBigBlind}',
                      isSelected: widget.selectedTier == tier,
                      color: tier.color,
                      onTap: () => widget.onTierSelected(tier),
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatefulWidget {
  final String label;
  final String? subtitle;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    this.subtitle,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  @override
  State<_FilterChip> createState() => _FilterChipState();
}

class _FilterChipState extends State<_FilterChip> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            gradient: widget.isSelected
                ? LinearGradient(
                    colors: [
                      widget.color.withOpacity(0.3),
                      widget.color.withOpacity(0.1),
                    ],
                  )
                : null,
            color: widget.isSelected ? null : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: widget.isSelected
                  ? widget.color
                  : Colors.white.withOpacity(0.1),
              width: widget.isSelected ? 2 : 1,
            ),
            boxShadow: widget.isSelected
                ? [
                    BoxShadow(
                      color: widget.color.withOpacity(0.5),
                      blurRadius: 15,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.label,
                style: TextStyle(
                  color: widget.isSelected ? widget.color : Colors.white70,
                  fontSize: 14,
                  fontWeight: widget.isSelected ? FontWeight.bold : FontWeight.w500,
                  letterSpacing: widget.isSelected ? 1 : 0,
                ),
              ),
              if (widget.subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  widget.subtitle!,
                  style: TextStyle(
                    color: widget.isSelected
                        ? widget.color.withOpacity(0.8)
                        : Colors.white38,
                    fontSize: 10,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
