import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/language_provider.dart';
import '../services/socket_service.dart';
import 'game_screen.dart';
import 'login_screen.dart';
import 'profile_screen.dart';
import '../widgets/add_credits_dialog.dart';
import '../widgets/withdraw_credits_dialog.dart';
import '../widgets/wallet_display.dart';
import 'club/club_dashboard_screen.dart';
import 'tournament/tournament_list_screen.dart';
import 'admin/admin_dashboard_screen.dart';
import '../widgets/poker_loading_indicator.dart';
import '../providers/club_provider.dart';

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  final TextEditingController _roomController = TextEditingController();
  bool _isCreating = false;
  bool _isJoining = false;
  bool _isLoadingClubs = false;
  bool _isLoadingTournaments = false;

  @override
  void dispose() {
    _roomController.dispose();
    super.dispose();
  }

  void _navigateToGame(String roomId, [Map<String, dynamic>? initialState]) async {
    // Show loading if not already shown by a button state
    // For practice/create/join, the button state handles the UI loader.
    // We just need to add the delay here or in the button handlers.
    // Let's add it in the button handlers for better control, or here if generic.
    // Since _navigateToGame is called after success, we can add delay here BUT
    // we need to make sure the button loader stays active.
    // The button handlers set _isCreating/_isJoining to true, call service, then false.
    // We should modify the button handlers to keep it true until after navigation/delay.
    
    final bool isPractice = initialState?['isPracticeMode'] ?? false;
    
    // Artificial delay
    await Future.delayed(const Duration(seconds: 1));

    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GameScreen(
          roomId: roomId,
          initialGameState: isPractice ? null : initialState,
          isPracticeMode: isPractice,
        ),
      ),
    );
  }

  void _showShareDialog(String roomId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('🎉 Sala Creada'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              'Comparte este código con tus amigos:',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.amber.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber, width: 2),
              ),
              child: SelectableText(
                roomId,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                  color: Colors.black,
                ),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: roomId));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✅ Código copiado al portapapeles'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copiar Código'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext); // Close dialog first
              _navigateToGame(roomId);
            },
            icon: const Icon(Icons.play_arrow),
            label: const Text('Ir a la Sala'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);
    final socketService = Provider.of<SocketService>(context);

    // Imperial Palette Colors
    const Color goldColor = Color(0xFFC89A4E);
    const Color darkGreenColor = Color(0xFF4F7F6C);
    const Color blackColor = Color(0xFF1C1C1C);
    const Color beigeColor = Color(0xFFF1E3D3);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/poker_background.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withOpacity(0.7),
                Colors.black.withOpacity(0.85),
                Colors.black.withOpacity(0.9),
              ],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                // Header with wallet, language toggle, and sign out
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Sign out button
                      IconButton(
                        onPressed: () async {
                          final authProvider = context.read<AuthProvider>();
                          await authProvider.signOut();
                          if (context.mounted) {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(builder: (_) => const LoginScreen()),
                            );
                          }
                        },
                        icon: const Icon(Icons.logout, color: Colors.white70),
                        tooltip: languageProvider.currentLocale.languageCode == 'en' ? 'Sign Out' : 'Cerrar Sesión',
                      ),
                      
                      // Admin Button (Only visible if admin)
                      Consumer<ClubProvider>(
                        builder: (context, clubProvider, _) {
                          // Ensure we have the latest role
                          if (clubProvider.currentUserRole == 'admin') {
                            return IconButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
                                );
                              },
                              icon: const Icon(Icons.admin_panel_settings, color: Colors.redAccent),
                              tooltip: 'Super Admin Dashboard',
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),

                      const Spacer(),
                      // Profile Avatar Button
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const ProfileScreen()),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: goldColor,
                              width: 2,
                            ),
                          ),
                          child: Consumer<AuthProvider>(
                            builder: (context, authProvider, _) {
                              final user = authProvider.user;
                              return CircleAvatar(
                                radius: 18,
                                backgroundColor: goldColor,
                                backgroundImage: user?.photoURL != null
                                    ? NetworkImage(user!.photoURL!)
                                    : null,
                                child: user?.photoURL == null
                                    ? Text(
                                        (user?.displayName?.isNotEmpty == true
                                            ? user!.displayName![0].toUpperCase()
                                            : user?.email?[0].toUpperCase() ?? '?'),
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      )
                                    : null,
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Wallet and controls
                      Row(
                        children: [
                          // Wallet Display
                          const WalletDisplay(),
                          const SizedBox(width: 12),
                          // Language Toggle
                          GestureDetector(
                            onTap: () => languageProvider.toggleLanguage(),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(25),
                                border: Border.all(color: goldColor, width: 1.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    languageProvider.currentLocale.languageCode == 'en' ? '🇺🇸' : '🇪🇸',
                                    style: const TextStyle(fontSize: 22),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    languageProvider.currentLocale.languageCode == 'en' ? 'EN' : 'ES',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                // Main content
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Title
                          const Text(
                            'POKER IMPERIAL',
                            style: TextStyle(
                              fontSize: 52,
                              fontWeight: FontWeight.bold,
                              color: goldColor,
                              letterSpacing: 4,
                              shadows: [
                                Shadow(
                                  color: Colors.black87,
                                  blurRadius: 15,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 40),
                          
                          // Connection Status
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            decoration: BoxDecoration(
                              color: socketService.isConnected 
                                  ? Colors.green.withOpacity(0.2) 
                                  : Colors.red.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: socketService.isConnected 
                                    ? Colors.green.withOpacity(0.5) 
                                    : Colors.red.withOpacity(0.5),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  socketService.isConnected ? Icons.wifi : Icons.wifi_off,
                                  color: socketService.isConnected ? Colors.green : Colors.red,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  socketService.isConnected 
                                      ? languageProvider.getText('connected')
                                      : languageProvider.getText('connecting'),
                                  style: TextStyle(
                                    color: socketService.isConnected ? Colors.green : Colors.red,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 40),

                          // Clubs and Tournaments Buttons (Moved to Top)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildFeatureButton(
                                context,
                                icon: Icons.shield,
                                label: 'Clubs',
                                color: darkGreenColor,
                                isLoading: _isLoadingClubs,
                                onTap: _isLoadingClubs ? null : () async {
                                  setState(() => _isLoadingClubs = true);
                                  await Future.delayed(const Duration(seconds: 1));
                                  if (mounted) {
                                    setState(() => _isLoadingClubs = false);
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => const ClubDashboardScreen()),
                                    );
                                  }
                                },
                              ),
                              const SizedBox(width: 20),
                              _buildFeatureButton(
                                context,
                                icon: Icons.emoji_events,
                                label: 'Tournaments',
                                color: goldColor,
                                isLoading: _isLoadingTournaments,
                                onTap: _isLoadingTournaments ? null : () async {
                                  setState(() => _isLoadingTournaments = true);
                                  await Future.delayed(const Duration(seconds: 1));
                                  if (mounted) {
                                    setState(() => _isLoadingTournaments = false);
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => const TournamentListScreen()),
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 40),

                          // --- JOIN ROOM SECTION ---
                          Container(
                            constraints: const BoxConstraints(maxWidth: 450),
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: goldColor.withOpacity(0.3)),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  languageProvider.currentLocale.languageCode == 'en' 
                                      ? 'Join a Room' 
                                      : 'Unirse a una Sala',
                                  style: const TextStyle(
                                    color: goldColor,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _roomController,
                                        style: const TextStyle(color: beigeColor, fontSize: 16),
                                        decoration: InputDecoration(
                                          labelText: languageProvider.getText('room_id'),
                                          labelStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
                                          filled: true,
                                          fillColor: Colors.black.withOpacity(0.4),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(12),
                                            borderSide: BorderSide.none,
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(12),
                                            borderSide: BorderSide(color: goldColor.withOpacity(0.3), width: 1),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(12),
                                            borderSide: const BorderSide(color: goldColor, width: 2),
                                          ),
                                          prefixIcon: const Icon(Icons.meeting_room, color: goldColor),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        gradient: const LinearGradient(
                                          colors: [Color(0xFF4CAF50), Color(0xFF2E7D32)],
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.green.withOpacity(0.3),
                                            blurRadius: 8,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: ElevatedButton(
                                        onPressed: _isJoining ? null : () {
                                          final authProvider = Provider.of<AuthProvider>(context, listen: false);
                                          final userName = authProvider.user?.displayName ?? 'Player';
                                          
                                          if (_roomController.text.isNotEmpty) {
                                            setState(() => _isJoining = true);
                                            socketService.joinRoom(
                                              _roomController.text,
                                              userName,
                                              onSuccess: (roomId) async {
                                                // Delay handled in _navigateToGame, but we need to keep _isJoining true
                                                // actually _navigateToGame is async now, so we await it?
                                                // No, onSuccess is a callback. 
                                                // We should wait here before calling _navigateToGame? 
                                                // _navigateToGame has the delay.
                                                // We just need to NOT set _isJoining = false immediately.
                                                await _navigateToGameWithDelay(roomId);
                                                if (mounted) setState(() => _isJoining = false);
                                              },
                                              onError: (error) {
                                                setState(() => _isJoining = false);
                                                if (error.contains('Insufficient balance')) {
                                                  showDialog(
                                                    context: context,
                                                    builder: (_) => const AddCreditsDialog(),
                                                  );
                                                } else {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(content: Text('Error: $error')),
                                                  );
                                                }
                                              },
                                            );
                                          }
                                        },
                                        style: ElevatedButton.styleFrom(
                                          minimumSize: const Size(100, 56),
                                          backgroundColor: Colors.transparent,
                                          shadowColor: Colors.transparent,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                        ),
                                        child: _isJoining
                                          ? const SizedBox(
                                              height: 24,
                                              width: 24,
                                                child: PokerLoadingIndicator(size: 24, color: Colors.white),
                                            )
                                          : Text(
                                              languageProvider.getText('join').toUpperCase(),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                                color: Colors.white,
                                                letterSpacing: 1.0,
                                              ),
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          
                          const SizedBox(height: 40),
                          
                          // Divider
                          Row(
                            children: [
                              Expanded(child: Divider(color: Colors.white.withOpacity(0.1), thickness: 1)),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Icon(Icons.star, color: goldColor.withOpacity(0.5), size: 16),
                              ),
                              Expanded(child: Divider(color: Colors.white.withOpacity(0.1), thickness: 1)),
                            ],
                          ),
                          
                          const SizedBox(height: 40),
                          
                          // --- ACTIONS SECTION (Practice & Create) ---
                          
                          // Play Now Button (Practice)
                          Container(
                            constraints: const BoxConstraints(maxWidth: 400),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: const LinearGradient(
                                colors: [Color(0xFFFFD700), Color(0xFFB8860B)], // Gold Gradient
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: goldColor.withOpacity(0.3),
                                  blurRadius: 12,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: ElevatedButton(
                              onPressed: (_isCreating || _isJoining) ? null : () async {
                                setState(() => _isCreating = true); // Reuse isCreating for practice loading
                                await _navigateToGameWithDelay('practice', {'isPracticeMode': true});
                                if (mounted) setState(() => _isCreating = false);
                              },
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size(double.infinity, 60),
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                foregroundColor: blackColor,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: _isCreating
                                ? const SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: PokerLoadingIndicator(size: 24, color: blackColor),
                                  )
                                : Text(
                                    languageProvider.getText('practice_bots').toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 2,
                                    ),
                                  ),
                            ),
                          ),
                          
                          const SizedBox(height: 20),
                          
                          // Create Room Button
                          Container(
                            constraints: const BoxConstraints(maxWidth: 400),
                            child: OutlinedButton(
                              onPressed: _isCreating ? null : () {
                                final authProvider = Provider.of<AuthProvider>(context, listen: false);
                                final userName = authProvider.user?.displayName ?? 'Player';
                                
                                setState(() => _isCreating = true);
                                socketService.createRoom(
                                  userName,
                                  onSuccess: (roomId) async {
                                    await Future.delayed(const Duration(seconds: 1));
                                    if (mounted) {
                                      setState(() => _isCreating = false);
                                      _showShareDialog(roomId);
                                    }
                                  },
                                  onError: (error) {
                                    setState(() => _isCreating = false);
                                    if (error.contains('Insufficient balance')) {
                                      showDialog(
                                        context: context,
                                        builder: (_) => const AddCreditsDialog(),
                                      );
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Error: $error')),
                                      );
                                    }
                                  },
                                );
                              },
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(double.infinity, 60),
                                foregroundColor: goldColor,
                                side: const BorderSide(color: goldColor, width: 2),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: _isCreating 
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: PokerLoadingIndicator(size: 20, color: goldColor),
                                  )
                                : Text(
                                    languageProvider.getText('create_room').toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 2,
                                    ),
                                  ),
                            ),
                          ),
                          
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Helper for async navigation with delay
  Future<void> _navigateToGameWithDelay(String roomId, [Map<String, dynamic>? initialState]) async {
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;
    _navigateToGame(roomId, initialState);
  }

  Widget _buildFeatureButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
    bool isLoading = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 140,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Column(
          children: [
            isLoading 
              ? SizedBox(
                  height: 32,
                  width: 32,
                  child: PokerLoadingIndicator(size: 32, color: color),
                )
              : Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
