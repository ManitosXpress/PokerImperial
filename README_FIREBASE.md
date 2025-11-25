# 🎰 Poker Imperial - Firebase Authentication & Credits System

## 📋 Overview

This system implements a **server-authoritative** authentication and in-game credits economy for the Poker Imperial game using Firebase. The architecture is designed to facilitate future blockchain migration with minimal code changes.

## ✨ Key Features

- 🔐 **Firebase Authentication**
  - Email/Password registration and login
  - Google Sign-In integration
  - Automatic user profile creation

- 💰 **Secure Credits System**
  - **Server-authoritative**: All balance modifications happen via Cloud Functions
  - **Atomic transactions**: Prevents race conditions and double-spending
  - **Immutable audit trail**: Every transaction logged with SHA-256 hash
  - **Real-time updates**: Balance updates instantly across all devices

- 🔒 **Security First**
  - Firestore security rules prevent direct client writes
  - Users can READ their balance but NEVER WRITE it
  - Only Cloud Functions (Admin SDK) can modify balances

- 🚀 **Blockchain Ready**
  - Transaction logs include cryptographic hashes
  - Architecture designed for easy token migration
  - Deposit/withdrawal flows ready for blockchain integration

## 📁 Project Structure

```
Poker/
├── app/                        # Flutter app
│   ├── lib/
│   │   ├── services/
│   │   │   ├── auth_service.dart          # Firebase Auth wrapper
│   │   │   └── credits_service.dart       # Cloud Functions client
│   │   ├── providers/
│   │   │   ├── auth_provider.dart         # Auth state management
│   │   │   └── wallet_provider.dart       # Wallet state management
│   │   ├── screens/
│   │   │   ├── login_screen.dart          # Login/Registration UI
│   │   │   └── lobby_screen.dart          # Main lobby (updated)
│   │   └── widgets/
│   │       ├── wallet_display.dart        # Balance widget
│   │       └── add_credits_dialog.dart    # Add credits UI
│   ├── firestore.rules         # Security rules
│   └── firebase.json           # Firebase config
│
└── functions/                  # Cloud Functions
    ├── src/
    │   ├── index.ts           # Main entry point
    │   ├── functions/
    │   │   └── credits.ts     # Credit management functions
    │   └── utils/
    │       └── hash.ts        # SHA-256 hashing utility
    ├── package.json
    └── tsconfig.json
```

## 🚀 Quick Start

### Prerequisites

- Node.js 18+
- Flutter SDK
- Firebase CLI (`npm install -g firebase-tools`)
- Firebase project created

### 1. Install Dependencies

**Cloud Functions:**
```bash
cd functions
npm install
```

**Flutter App:**
```bash
cd app
flutter pub get
```

### 2. Configure Firebase

```bash
cd app
firebase login
flutterfire configure
```

### 3. Deploy to Firebase

**Deploy Cloud Functions:**
```bash
cd functions
npm run build
firebase deploy --only functions
```

**Deploy Security Rules:**
```bash
cd app
firebase deploy --only firestore:rules
```

### 4. Run the App

```bash
cd app
flutter run
```

## 📚 Detailed Documentation

- **[Deployment Guide](./deployment_guide.md)** - Complete step-by-step deployment instructions
- **[Implementation Plan](./implementation_plan.md)** - Technical architecture and design decisions

## 🎮 How to Use

### For Players

1. **Sign Up / Login**
   - Email/Password or Google Sign-In
   - Profile created automatically

2. **Add Credits**
   - Click "Agregar" (Add) button in lobby
   - Select amount or enter custom amount
   - Credits added instantly

3. **Play Poker**
   - Credits automatically deducted when joining games
   - Winnings automatically added to balance

### For Developers

**Add Credits (Simulates Purchase):**
```dart
final walletProvider = context.read<WalletProvider>();
await walletProvider.addCredits(1000, 'purchase');
```

**Deduct Credits (Game Entry):**
```dart
final success = await walletProvider.deductCredits(
  100,
  'game_entry',
  metadata: {'roomId': roomId, 'tableId': tableId},
);

if (!success) {
  showInsufficientBalanceDialog();
}
```

**Listen to Balance Changes:**
```dart
StreamBuilder<double>(
  stream: creditsService.getWalletBalanceStream(),
  builder: (context, snapshot) {
    return Text('Balance: ${snapshot.data}');
  },
)
```

## 🔐 Security Architecture

### Firestore Security Rules

```javascript
// Users can READ their data but NEVER WRITE
match /users/{userId} {
  allow read: if request.auth.uid == userId;
  allow write: if false;  // Only Cloud Functions can write
}

// Transaction logs are READ-ONLY for users
match /transaction_logs/{logId} {
  allow read: if resource.data.userId == request.auth.uid;
  allow write: if false;  // Only Cloud Functions can write
}
```

### Cloud Functions (Server-Authoritative)

All balance modifications go through Cloud Functions:

- **`addCreditsFunction`**: Adds credits (purchases, rewards, deposits)
- **`deductCreditsFunction`**: Deducts credits (game entry, purchases)

Both use **Firestore transactions** to ensure atomicity and prevent race conditions.

## 🔗 Blockchain Migration Path

The system is ready for blockchain integration:

### Future: Deposit Flow
```typescript
// Listen to blockchain deposit events
functions.firestore.document('blockchain_deposits/{depositId}')
  .onCreate(async (snap, context) => {
    const deposit = snap.data();
    await addCredits(deposit.userId, deposit.amount, 'blockchain_deposit');
  });
```

### Future: Withdrawal Flow
```typescript
export const requestWithdrawal = functions.https.onCall(async (data, context) => {
  await deductCredits(data.userId, data.amount, 'withdrawal_pending');
  await createBlockchainWithdrawal(data.userId, data.amount, data.walletAddress);
});
```

## 📊 Firestore Collections

### `users/{uid}`
- `uid`: User ID
- `email`: User email
- `nickname`: Display name
- `walletBalance`: Current balance (READ-ONLY for clients)
- `createdAt`: Account creation timestamp
- `lastUpdated`: Last balance update timestamp

### `transaction_logs/{transactionId}`
- `userId`: User ID
- `amount`: Transaction amount
- `type`: "credit" | "debit"
- `reason`: "purchase" | "game_entry" | "game_win" | etc.
- `timestamp`: Transaction time
- `beforeBalance`: Balance before transaction
- `afterBalance`: Balance after transaction
- `hash`: SHA-256 hash for audit trail
- `metadata`: Additional data (gameId, tableId, etc.)

## 🧪 Testing

### Test Authentication
1. Register new user
2. Sign in with Google
3. Logout and login again

### Test Credits
1. Add 1000 credits
2. Check balance updates
3. View transaction logs in Firestore
4. Verify hash integrity

### Test Security
1. Try to edit balance in Firestore (should fail)
2. Test concurrent transactions
3. Verify transaction atomicity

## 💡 Tips

- **Free Tier**: Firebase free tier includes 2M function invocations/month
- **Costs**: Monitor usage in Firebase Console
- **Indexes**: Firestore will auto-create needed indexes
- **Testing**: Use Firebase Emulators for local testing

## 🛠️ Troubleshooting

See [Deployment Guide](./deployment_guide.md#troubleshooting) for common issues and solutions.

## 📝 License

This project is part of Poker Imperial game system.

---

**Built with**: Flutter, Firebase Auth, Cloud Firestore, Cloud Functions  
**Architecture**: Server-Authoritative with Blockchain-Ready Design
