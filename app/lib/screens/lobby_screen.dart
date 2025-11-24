import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/socket_service.dart';
import '../providers/language_provider.dart';
import 'game_screen.dart';

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

  void _navigateToGame(String roomId) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GameScreen(roomId: roomId)),
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
      appBar: AppBar(
        title: const Text('Poker Lobby'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: GestureDetector(
              onTap: () => languageProvider.toggleLanguage(),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  children: [
                    Text(
                      languageProvider.currentLocale.languageCode == 'en' ? '🇺🇸' : '🇪🇸',
                      style: const TextStyle(fontSize: 20),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      languageProvider.currentLocale.languageCode == 'en' ? 'EN' : 'ES',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!socketService.isConnected)
              Text(languageProvider.getText('connecting'), style: const TextStyle(color: Colors.red))
            else
              Text(languageProvider.getText('connected'), style: const TextStyle(color: Colors.green)),
            const SizedBox(height: 20),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: languageProvider.getText('your_name'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 40),
            ElevatedButton(
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
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: $error')),
                      );
                    },
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                backgroundColor: const Color(0xFFE94560),
              ),
              child: _isCreating 
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : Text(languageProvider.getText('create_room')),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                if (_nameController.text.isNotEmpty) {
                  socketService.createPracticeRoom(
                    _nameController.text,
                    onSuccess: (roomId) {
                      _navigateToGame(roomId);
                    },
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                backgroundColor: Colors.blue,
              ),
              child: Text(languageProvider.getText('practice_bots')),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _roomController,
                    decoration: InputDecoration(
                      labelText: languageProvider.getText('room_id'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
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
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error: $error')),
                          );
                        },
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(100, 50),
                  ),
                  child: _isJoining
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(languageProvider.getText('join')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
