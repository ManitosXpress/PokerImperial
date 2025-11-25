import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'services/socket_service.dart';
import 'providers/language_provider.dart';
import 'screens/lobby_screen.dart';

import 'dart:async';

void main() {
  runZonedGuarded(() {
    // Set up error widget for build errors
    ErrorWidget.builder = (FlutterErrorDetails details) {
      return Material(
        color: Colors.red.shade900,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Application Error',
                  style: TextStyle(fontSize: 24, color: Colors.white, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                Text(
                  details.exception.toString(),
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
                const SizedBox(height: 20),
                Text(
                  'Stack Trace:',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                Text(
                  details.stack.toString(),
                  style: const TextStyle(color: Colors.white70, fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
        ),
      );
    };
    
    runApp(const PokerApp());
  }, (error, stackTrace) {
    // Log async errors
    print('Caught error: $error');
    print(stackTrace);
  });
}

class PokerApp extends StatelessWidget {
  const PokerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SocketService()..connect()),
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
      ],
      child: MaterialApp(
        title: 'Poker Texas Holdem',
        theme: ThemeData(
          brightness: Brightness.dark,
          primaryColor: const Color(0xFF1A1A2E),
          scaffoldBackgroundColor: const Color(0xFF16213E),
          textTheme: GoogleFonts.outfitTextTheme(
            Theme.of(context).textTheme.apply(bodyColor: Colors.white, displayColor: Colors.white),
          ),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFE94560),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'POKER IMPERIAL',
                  style: TextStyle(
                    fontSize: 52,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 4.0,
                    color: Color(0xFFE94560),
                    shadows: [
                      Shadow(
                        color: Colors.black87,
                        blurRadius: 15,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 80),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const LobbyScreen()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE94560),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 65),
                      elevation: 8,
                      shadowColor: const Color(0xFFE94560).withOpacity(0.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'PLAY NOW',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
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
