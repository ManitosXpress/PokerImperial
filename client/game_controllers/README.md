# Game Controllers - Practice Mode Implementation

This directory contains the client-side game controllers for poker gameplay, implementing a **Strategy Pattern** to separate Practice Mode from Real Money Mode.

## 🎮 Practice Mode (Offline)

**CRITICAL**: Practice mode has **ZERO Firebase dependencies** and does **NOT** touch real credits.

### Architecture

```
IPokerGameController (interface)
├── PracticeGameController ✅ (Implemented)
│   ├── PokerStateMachine (FSM for game flow)
│   ├── HandEvaluator (Winner determination + side pots)
│   └── BotAI (Intelligent bot decisions)
└── RealMoneyGameController ⏳ (Future - server-connected)
```

### Files

- **`IPokerGameController.ts`**: Interface defining the contract for all game controllers
- **`types.ts`**: Shared type definitions (Player, GameState, Card, etc.)
- **`PracticeGameController.ts`**: Complete offline game logic with bots
- **`PokerStateMachine.ts`**: Finite State Machine for Texas Hold'em flow
- **`HandEvaluator.ts`**: Hand ranking, side pots, split pots
- **`BotAI.ts`**: Intelligent bot decision-making
- **`GameControllerFactory.ts`**: Factory for creating controllers

## 🚀 Usage

### Quick Start (Practice Mode)

```typescript
import { GameControllerFactory } from './game_controllers/GameControllerFactory';

// Create a practice game (automatically adds 7 bots)
const controller = GameControllerFactory.createPracticeGame(
  'user-123',
  'John Doe'
);

// Subscribe to game state changes
controller.onGameStateChange = (state) => {
  console.log('Game state updated:', state);
  // Update UI here
};

// Player takes action
controller.handleAction('user-123', 'call');
controller.handleAction('user-123', 'bet', 100);
controller.handleAction('user-123', 'fold');
```

### Manual Setup

```typescript
import { PracticeGameController } from './game_controllers/PracticeGameController';
import { Player } from './game_controllers/types';

const controller = new PracticeGameController('user-123', 'John Doe');

const players: Player[] = [
  {
    id: 'user-123',
    name: 'John Doe',
    chips: 0, // Controller sets this
    currentBet: 0,
    isFolded: false,
    isBot: false
  }
];

controller.startGame(players); // Adds 7 bots automatically
```

## 🤖 Bot Features

- **Hand Strength Evaluation**: Premium hands (AA, KK) → Aggressive
- **Position Awareness**: Adjusts play based on position
- **Pot Odds**: Considers pot odds for call decisions
- **Realistic Names**: 50+ unique international names
- **Thinking Delays**: 1-3 second delays to simulate human play

## 🎰 Game Features

### Texas Hold'em Rules
- ✅ Pre-flop, Flop, Turn, River, Showdown
- ✅ Blinds (Small blind: 10, Big blind: 20)
- ✅ All betting actions (Fold, Check, Call, Bet, Raise, All-in)
- ✅ All-in scenarios (auto-advance to showdown)

### Advanced Features
- ✅ **Side Pots**: Handles multiple all-ins at different amounts
- ✅ **Split Pots**: Distributes tied hands fairly
- ✅ **Rake**: 10% house rake on winnings
- ✅ **Demo Chips**: Each player starts with 10,000 demo chips

### State Machine
Enforces valid state transitions:
```
WaitingForPlayers → PostingBlinds → PreFlop → Flop → Turn → River → Showdown
```

## 🔒 Security

**Practice Mode Isolation**:
- ❌ NO Firebase imports
- ❌ NO Firestore access
- ❌ NO real credit deduction
- ❌ NO API calls
- ✅ All state in memory (RAM)
- ✅ Resets on page refresh

## 📊 Game State

The `GameState` object contains:
```typescript
{
  pot: number;
  communityCards: string[];  // e.g., ["Ah", "Kd", "Qc"]
  currentTurn: string;        // Player ID
  dealerId: string;
  round: GameStateEnum;       // 'pre-flop', 'flop', etc.
  currentBet: number;
  minBet: number;
  players: Player[];
}
```

## 🧪 Integration with Flutter

To use in Flutter UI:

1. **Import the factory**:
```dart
// In your Dart code, you'll call the TypeScript controller via a bridge
// Example using js interop or method channels
```

2. **Subscribe to state changes**:
```typescript
controller.onGameStateChange = (state) => {
  // Send state to Flutter UI
  window.postMessage({ type: 'gameState', state }, '*');
};
```

3. **Handle player actions**:
```typescript
// Listen for actions from Flutter
window.addEventListener('message', (event) => {
  if (event.data.type === 'playerAction') {
    controller.handleAction(
      event.data.playerId,
      event.data.action,
      event.data.amount
    );
  }
});
```

## 🎯 Next Steps

For complete integration with your Flutter app:

1. Install pokersolver dependency: `npm install pokersolver`
2. Create a bridge between TypeScript and Dart
3. Update `LobbyScreen.dart` to offer practice mode button
4. Update `GameScreen.dart` to accept controller instance
5. Add "PRACTICE MODE" banner in UI

## 📝 Notes

- Demo chips reset on page refresh (intentional for practice mode)
- Bots make decisions based on hand strength and position
- Side pots automatically calculated for complex all-in scenarios
- 10% rake applied to all winnings (practice mode doesn't send rake anywhere)

---

**Remember**: This is PRACTICE MODE only. No real money or credits are involved!
