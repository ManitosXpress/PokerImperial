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

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _roomController = TextEditingController();
  bool _isCreating = false;
  bool _isJoining = false;

  @override
  void dispose() {
    _nameController.dispose();
    _roomController.dispose();
    super.dispose();
  }

  void _navigateToGame(String roomId, [Map<String, dynamic>? initialState]) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GameScreen(
          roomId: roomId,
          initialGameState: initialState,
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
                              color: const Color(0xFFE94560),
                              width: 2,
                            ),
                          ),
                          child: Consumer<AuthProvider>(
                            builder: (context, authProvider, _) {
                              final user = authProvider.user;
                              return CircleAvatar(
                                radius: 18,
                                backgroundColor: const Color(0xFFE94560),
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
                          // Add Credits Button
                          ElevatedButton.icon(
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (_) => const AddCreditsDialog(),
                              );
                            },
                            icon: const Icon(Icons.add, size: 18),
                            label: Text(
                              languageProvider.currentLocale.languageCode == 'en' ? 'Add' : 'Agregar',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFe94560),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Withdraw Credits Button
                          ElevatedButton.icon(
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (_) => const WithdrawCreditsDialog(),
                              );
                            },
                            icon: Icon(Icons.remove, size: 18, color: Colors.lightBlue.shade100),
                            label: Text(
                              languageProvider.currentLocale.languageCode == 'en' ? 'Withdraw' : 'Retirar',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
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
                                border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
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
                              color: Color(0xFFE94560),
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
                          const SizedBox(height: 60),
                          
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
                          
                          // Name Input
                          Container(
                            constraints: const BoxConstraints(maxWidth: 400),
                            child: TextField(
                              controller: _nameController,
                              style: const TextStyle(color: Colors.white, fontSize: 16),
                              decoration: InputDecoration(
                                labelText: languageProvider.getText('your_name'),
                                labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.1),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Color(0xFFE94560), width: 2),
                                ),
                                prefixIcon: const Icon(Icons.person, color: Colors.white70),
                              ),
                            ),
                          ),
                          const SizedBox(height: 50),
                          
                          // Play Now Button (main CTA)
                          Container(
                            constraints: const BoxConstraints(maxWidth: 400),
                            child: ElevatedButton(
                              onPressed: (_isCreating || _isJoining) ? null : () {
                                if (_nameController.text.isNotEmpty) {
                                  setState(() => _isCreating = true); // Reuse _isCreating for simplicity or add _isPracticeLoading
                                  socketService.createPracticeRoom(
                                    _nameController.text,
                                    onSuccess: (data) {
                                      setState(() => _isCreating = false);
                                      final roomId = data['roomId'];
                                      if (roomId != null) {
                                        try {
                                          final Map<String, dynamic> state = Map<String, dynamic>.from(data as Map);
                                          _navigateToGame(roomId, state);
                                        } catch (e) {
                                          print('Error casting game state: $e');
                                          _navigateToGame(roomId);
                                        }
                                      }
                                    },
                                    onError: (error) {
                                      setState(() => _isCreating = false);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Error: $error'),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    },
                                  );
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size(double.infinity, 65),
                                backgroundColor: const Color(0xFFE94560),
                                foregroundColor: Colors.white,
                                elevation: 8,
                                shadowColor: const Color(0xFFE94560).withOpacity(0.5),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: _isCreating
                                ? const SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                                  )
                                : Text(
                                    languageProvider.getText('practice_bots').toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 20,
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
                            child: ElevatedButton(
                              onPressed: _isCreating ? null : () {
                                if (_nameController.text.isNotEmpty) {
                                  setState(() => _isCreating = true);
                                  socketService.createRoom(
                                    _nameController.text,
                                    onSuccess: (roomId) {
                                      setState(() => _isCreating = false);
                                      _showShareDialog(roomId);
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
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size(double.infinity, 65),
                                backgroundColor: Colors.white.withOpacity(0.15),
                                foregroundColor: Colors.white,
                                elevation: 4,
                                side: BorderSide(color: Colors.white.withOpacity(0.5), width: 2),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: _isCreating 
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                  )
                                : Text(
                                    languageProvider.getText('create_room').toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 2,
                                    ),
                                  ),
                            ),
                          ),
                          const SizedBox(height: 50),
                          
                          // Divider
                          Row(
                            children: [
                              Expanded(child: Divider(color: Colors.white.withOpacity(0.2), thickness: 1)),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Text(
                                  languageProvider.currentLocale.languageCode == 'en' ? 'OR' : 'O',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.5),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Expanded(child: Divider(color: Colors.white.withOpacity(0.2), thickness: 1)),
                            ],
                          ),
                          const SizedBox(height: 30),
                          
                          // Join Room Section
                          Container(
                            constraints: const BoxConstraints(maxWidth: 400),
                            child: Column(
                              children: [
                                Text(
                                  languageProvider.currentLocale.languageCode == 'en' 
                                      ? 'Join a Friend\'s Room' 
                                      : 'Unirse a una Sala',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.9),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _roomController,
                                        style: const TextStyle(color: Colors.white, fontSize: 16),
                                        decoration: InputDecoration(
                                          labelText: languageProvider.getText('room_id'),
                                          labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                                          filled: true,
                                          fillColor: Colors.white.withOpacity(0.1),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(12),
                                            borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(12),
                                            borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(12),
                                            borderSide: const BorderSide(color: Colors.blue, width: 2),
                                          ),
                                          prefixIcon: const Icon(Icons.meeting_room, color: Colors.white70),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    ElevatedButton(
                                      onPressed: _isJoining ? null : () {
                                        if (_nameController.text.isNotEmpty && _roomController.text.isNotEmpty) {
                                          setState(() => _isJoining = true);
                                          socketService.joinRoom(
                                            _roomController.text,
                                            _nameController.text,
                                            onSuccess: (roomId) {
                                              setState(() => _isJoining = false);
                                              _navigateToGame(roomId);
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
                                        minimumSize: const Size(120, 56),
                                        backgroundColor: Colors.blue.shade700,
                                        foregroundColor: Colors.white,
                                        elevation: 5,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                      child: _isJoining
                                        ? const SizedBox(
                                            height: 20,
                                            width: 20,
                                            child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : Text(
                                            languageProvider.getText('join').toUpperCase(),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                    ),
                                  ],
                                ),
                              ],
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
}
