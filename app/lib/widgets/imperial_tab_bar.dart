import 'package:flutter/material.dart';
import 'dart:ui';

class ImperialTabBar extends StatefulWidget {
  final TabController controller;
  final List<ImperialTab> tabs;

  const ImperialTabBar({
    super.key,
    required this.controller,
    required this.tabs,
  });

  @override
  State<ImperialTabBar> createState() => _ImperialTabBarState();
}

class _ImperialTabBarState extends State<ImperialTabBar> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(() {
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 70,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        // Glassmorphism effect
        color: Colors.white.withOpacity(0.05),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFD700).withOpacity(0.1),
            blurRadius: 20,
            spreadRadius: 0,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Row(
            children: List.generate(widget.tabs.length, (index) {
              final isSelected = widget.controller.index == index;
              return Expanded(
                child: _ImperialTabButton(
                  tab: widget.tabs[index],
                  isSelected: isSelected,
                  onTap: () => widget.controller.animateTo(index),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _ImperialTabButton extends StatelessWidget {
  final ImperialTab tab;
  final bool isSelected;
  final VoidCallback onTap;

  const _ImperialTabButton({
    required this.tab,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        gradient: isSelected
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  tab.activeColor.withOpacity(0.3),
                  tab.activeColor.withOpacity(0.1),
                ],
              )
            : null,
        border: isSelected
            ? Border.all(
                color: tab.activeColor.withOpacity(0.5),
                width: 2,
              )
            : null,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                tab.icon,
                color: isSelected ? tab.activeColor : Colors.white54,
                size: 28,
              ),
              const SizedBox(height: 4),
              Text(
                tab.label,
                style: TextStyle(
                  color: isSelected ? tab.activeColor : Colors.white54,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  letterSpacing: isSelected ? 1 : 0,
                ),
              ),
              if (isSelected)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  height: 3,
                  width: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        tab.activeColor,
                        tab.activeColor.withOpacity(0.5),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: [
                      BoxShadow(
                        color: tab.activeColor.withOpacity(0.5),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class ImperialTab {
  final IconData icon;
  final String label;
  final Color activeColor;

  const ImperialTab({
    required this.icon,
    required this.label,
    this.activeColor = const Color(0xFFFFD700),
  });
}
