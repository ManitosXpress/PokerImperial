# Game Controllers - Client-Side

This directory contains the **client-side game controllers** for poker, completely separated from the server and Flutter app.

## 📁 Structure

```
client/
└── game_controllers/          # Client-side practice mode
    ├── types.ts               # Type definitions
    ├── IPokerGameController.ts
    ├── PracticeGameController.ts  ⭐ Main practice controller
    ├── HandEvaluator.ts
    ├── BotAI.ts
    ├── PokerStateMachine.ts
    ├── GameControllerFactory.ts
    └── ...

server/
└── src/
    └── game/                  # Server-side real money mode
        ├── PokerGame.ts       ⭐ Original server logic
        ├── BotLogic.ts
        └── RoomManager.ts
```

## 🎯 Purpose

**Client controllers** (`client/game_controllers/`):
- Practice mode ONLY
- 100% offline, no Firebase
- Demo chips (10,000 per player)
- Runs in browser/client

**Server controllers** (`server/src/game/`):
- Real money mode
- Connected to Firebase
- Real credit validation
- Runs on server

## 🚀 Usage

See [`QUICKSTART.md`](./game_controllers/QUICKSTART.md) for detailed instructions.

---

**Key**: Both use similar Texas Hold'em logic, but completely separated for security and clarity.
