import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/language_provider.dart';
import '../../utils/responsive_utils.dart';

class ActionControls extends StatefulWidget {
  final bool isTurn;
  final bool isSpectatorMode;
  final int currentBet;
  final int myCurrentBet;
  final int secondsRemaining;
  final Function(String, [int]) onAction;
  final VoidCallback onShowBetDialog;

  const ActionControls({
    super.key,
    required this.isTurn,
    required this.isSpectatorMode,
    required this.currentBet,
    required this.myCurrentBet,
    required this.secondsRemaining,
    required this.onAction,
    required this.onShowBetDialog,
  });

  @override
  State<ActionControls> createState() => _ActionControlsState();
}

class _ActionControlsState extends State<ActionControls> with SingleTickerProviderStateMixin {
  bool _isActionMenuExpanded = false;
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _toggleActionMenu() {
    setState(() {
      _isActionMenuExpanded = !_isActionMenuExpanded;
      if (_isActionMenuExpanded) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);
    final bool needToCall = widget.currentBet > widget.myCurrentBet;

    final bool isMobile = ResponsiveUtils.screenWidth(context) < 600;

    // If spectator, show indicator instead of controls
    if (widget.isSpectatorMode) {
      if (isMobile) {
        return Positioned(
          top: 80,
          right: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade700, Colors.blue.shade900],
              ),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.blue.shade300, width: 2),
            ),
            child: const Icon(Icons.remove_red_eye, color: Colors.white, size: 20),
          ),
        );
      }
      return Positioned(
        bottom: 30,
        left: ResponsiveUtils.screenWidth(context) / 2 + 80,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue.shade700, Colors.blue.shade900],
            ),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.blue.shade300, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withOpacity(0.5),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.remove_red_eye, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                'MODO ESPECTADOR',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (!widget.isTurn) return const SizedBox.shrink();

    // Mobile Positioning: Bottom Right
    // Desktop Positioning: Center + Offset
    
    final double toggleRight = isMobile ? 16 : 0;
    final double toggleLeft = isMobile ? 0 : ResponsiveUtils.screenWidth(context) / 2 + 80;
    final double toggleBottom = 30;

    return Stack(
      children: [
        // Turn Timer Widget
        Positioned(
          bottom: isMobile ? 100 : 30,
          left: isMobile ? 20 : ResponsiveUtils.screenWidth(context) / 2 - 120,
          child: SizedBox(
            width: 60,
            height: 60,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: widget.secondsRemaining / 5,
                  backgroundColor: Colors.grey.withOpacity(0.5),
                  color: widget.secondsRemaining <= 2 ? Colors.red : Colors.green,
                  strokeWidth: 6,
                ),
                Text(
                  '${widget.secondsRemaining}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 24,
                  ),
                ),
              ],
            ),
          ),
        ),
        
        // Raise/Bet button (3rd button)
        AnimatedBuilder(
          animation: _animation,
          builder: (context, child) {
            final offset = 30 + (70 * _animation.value * 3);
            return Positioned(
              bottom: offset,
              right: isMobile ? toggleRight : null,
              left: isMobile ? null : toggleLeft,
              child: Opacity(
                opacity: _animation.value,
                child: ScaleTransition(
                  scale: _animation,
                  child: FloatingActionButton.extended(
                    onPressed: () {
                      widget.onShowBetDialog();
                      _toggleActionMenu();
                    },
                    backgroundColor: Colors.green,
                    icon: const Icon(Icons.trending_up),
                    label: Text(languageProvider.getText('raise'), style: const TextStyle(fontWeight: FontWeight.bold)),
                    heroTag: 'raise',
                  ),
                ),
              ),
            );
          },
        ),
        
        // Call/Check button (2nd button)
        AnimatedBuilder(
          animation: _animation,
          builder: (context, child) {
            final offset = 30 + (70 * _animation.value * 2);
            return Positioned(
              bottom: offset,
              right: isMobile ? toggleRight : null,
              left: isMobile ? null : toggleLeft,
              child: Opacity(
                opacity: _animation.value,
                child: ScaleTransition(
                  scale: _animation,
                  child: FloatingActionButton.extended(
                    onPressed: () {
                      widget.onAction(needToCall ? 'call' : 'check');
                      _toggleActionMenu();
                    },
                    backgroundColor: Colors.blue,
                    icon: Icon(needToCall ? Icons.call_made : Icons.check_circle_outline),
                    label: Text(
                      needToCall ? '${languageProvider.getText('call')} ${widget.currentBet - widget.myCurrentBet}' : languageProvider.getText('check'),
                      style: const TextStyle(fontWeight: FontWeight.bold)
                    ),
                    heroTag: 'call_check',
                  ),
                ),
              ),
            );
          },
        ),
        
        // Fold button (1st button)
        AnimatedBuilder(
          animation: _animation,
          builder: (context, child) {
            final offset = 30 + (70 * _animation.value * 1);
            return Positioned(
              bottom: offset,
              right: isMobile ? toggleRight : null,
              left: isMobile ? null : toggleLeft,
              child: Opacity(
                opacity: _animation.value,
                child: ScaleTransition(
                  scale: _animation,
                  child: FloatingActionButton.extended(
                    onPressed: () {
                      widget.onAction('fold');
                      _toggleActionMenu();
                    },
                    backgroundColor: Colors.red,
                    icon: const Icon(Icons.close),
                    label: Text(languageProvider.getText('fold'), style: const TextStyle(fontWeight: FontWeight.bold)),
                    heroTag: 'fold',
                  ),
                ),
              ),
            );
          },
        ),
        
        // Main toggle button
        Positioned(
          bottom: toggleBottom,
          right: isMobile ? toggleRight : null,
          left: isMobile ? null : toggleLeft,
          child: FloatingActionButton(
            onPressed: _toggleActionMenu,
            backgroundColor: _isActionMenuExpanded ? Colors.grey[700] : Colors.amber,
            heroTag: 'menu_toggle',
            child: AnimatedRotation(
              turns: _isActionMenuExpanded ? 0.125 : 0,
              duration: const Duration(milliseconds: 250),
              child: const Icon(Icons.casino, size: 28),
            ),
          ),
        ),
      ],
    );
  }
}
