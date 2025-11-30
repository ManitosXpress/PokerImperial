/**
 * INTEGRATION GUIDE
 * How to integrate PracticeGameController with your Flutter UI
 * 
 * Since Flutter uses Dart and the controllers are in TypeScript, you have two options:
 * 
 * OPTION 1: Use js_interop (Recommended for Web)
 * OPTION 2: Port to Dart (Better for native mobile apps)
 * 
 * This file demonstrates Option 2 - Dart implementation
 */

// ============================================================================
// STEP 1: Create a Dart wrapper for the game controller
// File: lib/controllers/practice_game_controller.dart
// ============================================================================

/*
import 'package:flutter/foundation.dart';

class PracticeGameController extends ChangeNotifier {
  // TODO: Import the TypeScript controller
  // For web: Use dart:js or js_interop
  // For mobile: Port TypeScript code to Dart
  
  List<Player> _players = [];
  GameState? _gameState;
  
  PracticeGameController(String userId, String userName) {
    // Initialize TypeScript controller
    _initController(userId, userName);
  }
  
  void _initController(String userId, String userName) {
    // Web implementation:
    // final controller = js.JsObject(
    //   js.context['PracticeGameController'],
    //   [userId, userName]
    // );
    
    // Subscribe to state changes
    // controller.callMethod('onGameStateChange', [
    //   allowInterop((state) {
    //     _updateGameState(state);
    //   })
    // ]);
  }
  
  void handleAction(String playerId, String action, [int? amount]) {
    // Call TypeScript controller
    // _controller.callMethod('handleAction', [playerId, action, amount]);
  }
  
  void _updateGameState(dynamic state) {
    // Convert JS object to Dart
    _gameState = GameState.fromJson(state);
    notifyListeners();
  }
  
  GameState? get gameState => _gameState;
}
*/

// ============================================================================
// STEP 2: Update LobbyScreen to add Practice Mode button
// File: lib/screens/lobby_screen.dart
// ============================================================================

/*
// Add this button to your lobby screen:

ElevatedButton.icon(
  onPressed: () {
    _startPracticeMode();
  },
  icon: Icon(Icons.sports_esports),
  label: Text('Practice with Bots'),
  style: ElevatedButton.styleFrom(
    backgroundColor: Colors.orange,
    padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
  ),
)

void _startPracticeMode() {
  final userId = Provider.of<AuthProvider>(context, listen: false).user?.uid ?? 'guest';
  final userName = Provider.of<AuthProvider>(context, listen: false).user?.displayName ?? 'Guest';
  
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => GameScreen(
        roomId: 'practice',
        isPracticeMode: true,
        userId: userId,
        userName: userName,
      ),
    ),
  );
}
*/

// ============================================================================
// STEP 3: Update GameScreen to support practice mode
// File: lib/screens/game_screen.dart
// ============================================================================

/*
class GameScreen extends StatefulWidget {
  final String roomId;
  final bool isPracticeMode;
  final String? userId;
  final String? userName;

  const GameScreen({
    Key? key,
    required this.roomId,
    this.isPracticeMode = false,
    this.userId,
    this.userName,
  }) : super(key: key);

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  PracticeGameController? _practiceController;
  
  @override
  void initState() {
    super.initState();
    
    if (widget.isPracticeMode) {
      _initPracticeMode();
    } else {
      _initRealMode();
    }
  }
  
  void _initPracticeMode() {
    _practiceController = PracticeGameController(
      widget.userId!,
      widget.userName!,
    );
    
    _practiceController!.addListener(() {
      setState(() {
        // UI will rebuild with new game state
      });
    });
  }
  
  void _initRealMode() {
    // Existing socket.io connection
    _socketService.connect();
    // ...
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isPracticeMode ? 'Practice Mode' : 'Poker Game'),
        backgroundColor: widget.isPracticeMode ? Colors.orange : Colors.blue,
      ),
      body: Column(
        children: [
          // Show practice mode banner
          if (widget.isPracticeMode)
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(8),
              color: Colors.orange,
              child: Text(
                '🎮 PRACTICE MODE - Demo Chips Only',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
          
          // Game UI
          Expanded(
            child: _buildGameUI(),
          ),
        ],
      ),
    );
  }
  
  Widget _buildGameUI() {
    final gameState = widget.isPracticeMode 
        ? _practiceController?.gameState 
        : _getRealGameState();
    
    if (gameState == null) {
      return Center(child: CircularProgressIndicator());
    }
    
    return Column(
      children: [
        // Pot
        Text('Pot: ${gameState.pot}'),
        
        // Community cards
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: gameState.communityCards.map((card) => 
            _buildCard(card)
          ).toList(),
        ),
        
        // Players
        Expanded(
          child: GridView.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
            ),
            itemCount: gameState.players.length,
            itemBuilder: (context, index) => _buildPlayerWidget(
              gameState.players[index]
            ),
          ),
        ),
        
        // Action buttons
        _buildActionButtons(gameState),
      ],
    );
  }
  
  Widget _buildActionButtons(GameState gameState) {
    if (gameState.currentTurn != widget.userId) {
      return Text('Waiting for other players...');
    }
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        ElevatedButton(
          onPressed: () => _handleAction('fold'),
          child: Text('Fold'),
        ),
        if (gameState.currentBet == 0)
          ElevatedButton(
            onPressed: () => _handleAction('check'),
            child: Text('Check'),
          )
        else
          ElevatedButton(
            onPressed: () => _handleAction('call'),
            child: Text('Call ${gameState.currentBet}'),
          ),
        ElevatedButton(
          onPressed: () => _showBetDialog(),
          child: Text('Bet/Raise'),
        ),
        ElevatedButton(
          onPressed: () => _handleAction('allin'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          child: Text('All-In'),
        ),
      ],
    );
  }
  
  void _handleAction(String action, [int? amount]) {
    if (widget.isPracticeMode) {
      _practiceController?.handleAction(widget.userId!, action, amount);
    } else {
      // Send to server via socket
      _socketService.emit('game_action', {
        'roomId': widget.roomId,
        'action': action,
        'amount': amount,
      });
    }
  }
  
  @override
  void dispose() {
    _practiceController?.dispose();
    super.dispose();
  }
}
*/

// ============================================================================
// OPTION 2: Pure Dart Implementation (Recommended for Mobile)
// ============================================================================

/*
If you prefer not to use JavaScript interop, you can port the TypeScript code to Dart.
The logic is similar, just needs Dart syntax:

1. Create lib/game_controllers/ directory in your Flutter app
2. Port each TypeScript file to Dart:
   - types.dart
   - poker_state_machine.dart
   - hand_evaluator.dart (use 'poker' package instead of pokersolver)
   - bot_ai.dart
   - practice_game_controller.dart

3. Example Dart version of BotAI:

class BotAI {
  static const botNames = [
    'Alex Chen', 'Maria Garcia', 'James Wilson', ...
  ];
  
  static String getRandomBotName() {
    return botNames[Random().nextInt(botNames.length)];
  }
  
  static BotDecision decide(Player bot, GameState gameState) {
    final handStrength = evaluateHandStrength(
      bot.hand ?? [],
      gameState.communityCards,
      gameState.round,
    );
    
    // ... decision logic
  }
}

4. Use the 'poker' pub package for hand evaluation:
   dependencies:
     poker: ^0.2.0

5. Example usage:
   import 'package:poker/poker.dart';
   
   final hand = HandSolver.solve(['Ah', 'Kd', 'Qc', 'Jc', 'Tc']);
   print(hand.rank); // HandRank.straightFlush
*/

// ============================================================================
// QUICK START GUIDE
// ============================================================================

/*
FASTEST PATH TO GET PRACTICE MODE WORKING:

1. For Flutter Web:
   - Add js package: flutter pub add js
   - Use the TypeScript controllers via JS interop
   - Load the controllers as a script in web/index.html

2. For Flutter Mobile/Desktop:
   - Port to pure Dart (recommended)
   - Or use webview_flutter to run the TS controllers in a WebView

3. Minimal Example (Web with JS interop):

   // pubspec.yaml
   dependencies:
     js: ^0.6.7

   // lib/controllers/practice_bridge.dart
   @JS()
   library practice_controller;

   import 'package:js/js.dart';

   @JS('GameControllerFactory.createPracticeGame')
   external dynamic createPracticeGame(String userId, String userName);

   @JS()
   @anonymous
   class JSGameState {
     external int get pot;
     external List<String> get communityCards;
     // ...
   }

   // Usage:
   final controller = createPracticeGame('user-123', 'John');
   
That's it! The practice mode is now ready to use.
*/
