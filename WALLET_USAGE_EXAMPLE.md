# 🎮 Ejemplos de Uso - Sistema Wallet Premium

## 📋 Tabla de Contenidos
1. [Configuración Inicial](#configuración-inicial)
2. [Uso del WalletBadge](#uso-del-walletbadge)
3. [Uso del WalletDetailView](#uso-del-walletdetailview)
4. [Estructura de Datos Firestore](#estructura-de-datos-firestore)
5. [Ejemplos de Transacciones](#ejemplos-de-transacciones)

---

## 🚀 Configuración Inicial

### 1. Verificar que WalletProvider esté inicializado

En tu archivo principal (ej: `main.dart`):

```dart
import 'package:provider/provider.dart';
import 'package:app/providers/wallet_provider.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) {
            final walletProvider = WalletProvider();
            walletProvider.initialize(); // 👈 IMPORTANTE: Inicializar streams
            return walletProvider;
          },
        ),
        // ... otros providers
      ],
      child: MyApp(),
    ),
  );
}
```

---

## 💎 Uso del WalletBadge

### Ejemplo 1: En cualquier pantalla

```dart
import 'package:flutter/material.dart';
import 'package:app/widgets/game/wallet_badge.dart';

class MyGameScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Mi Juego'),
        actions: [
          // ✨ Badge premium en el AppBar
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: WalletBadge(),
          ),
        ],
      ),
      body: Center(
        child: Text('Contenido del juego'),
      ),
    );
  }
}
```

### Ejemplo 2: Como overlay flotante

```dart
Stack(
  children: [
    // Tu contenido principal
    MyGameContent(),
    
    // Badge flotante en la esquina superior derecha
    Positioned(
      top: 16,
      right: 16,
      child: WalletBadge(),
    ),
  ],
)
```

### Ejemplo 3: Personalizado con Hero Animation

```dart
Hero(
  tag: 'wallet-badge',
  child: WalletBadge(),
)
```

---

## 📊 Uso del WalletDetailView

### Ejemplo 1: Desde un botón

```dart
import 'package:app/widgets/game/wallet_detail_view.dart';

ElevatedButton(
  onPressed: () {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => WalletDetailView(),
    );
  },
  child: Text('Ver Historial'),
)
```

### Ejemplo 2: Como Dialog en Web/Desktop

```dart
// Para web, puedes usar un Dialog centrado
if (kIsWeb) {
  showDialog(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 500,
        height: 700,
        child: WalletDetailView(),
      ),
    ),
  );
} else {
  // Móvil usa bottom sheet (comportamiento por defecto)
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => WalletDetailView(),
  );
}
```

---

## 🗄️ Estructura de Datos Firestore

### Colección: `transaction_logs`

Cada documento debe tener la siguiente estructura:

```typescript
{
  // ✅ CAMPOS REQUERIDOS
  userId: "uid_del_usuario",          // String - Firebase UID
  type: "credit" | "debit",           // String - Tipo de transacción
  amount: 1000,                        // Number - Monto (siempre positivo)
  reason: "game_win",                  // String - Razón de la transacción
  timestamp: Timestamp.now(),          // Timestamp - Fecha/hora
  beforeBalance: 5000,                 // Number - Balance anterior
  afterBalance: 6000,                  // Number - Balance después
  hash: "abc123...",                   // String - Hash de verificación
  
  // ⚡ CAMPOS OPCIONALES
  metadata: {
    roomId?: "room_abc123",           // String - ID de la mesa
    gameType?: "texas_holdem",        // String - Tipo de juego
    opponentId?: "uid_opponent",      // String - ID del oponente
    ...                               // Cualquier dato adicional
  }
}
```

### Ejemplo de documento real:

```json
{
  "userId": "abc123xyz",
  "type": "credit",
  "amount": 500,
  "reason": "game_win",
  "timestamp": {
    "_seconds": 1702050000,
    "_nanoseconds": 0
  },
  "beforeBalance": 1000,
  "afterBalance": 1500,
  "hash": "sha256_hash_here",
  "metadata": {
    "roomId": "royal_flush_001",
    "gameType": "texas_holdem",
    "handRank": "Full House"
  }
}
```

---

## 💰 Ejemplos de Transacciones

### 1. Ganancia en Mesa (Verde ↑)

```json
{
  "userId": "player_123",
  "type": "credit",
  "amount": 750,
  "reason": "game_win",
  "timestamp": "2024-12-09T14:30:00Z",
  "metadata": {
    "roomId": "royal_flush_001",
    "pot": 1500,
    "handRank": "Royal Flush"
  }
}
```

**Resultado en UI:**
- 🟢 Icono de flecha arriba (verde)
- **Título:** "Mesa: royal_flush_001"
- **Fecha:** "Hoy, 14:30"
- **Monto:** +750 (verde)

---

### 2. Pérdida en Mesa (Rojo ↓)

```json
{
  "userId": "player_123",
  "type": "debit",
  "amount": 300,
  "reason": "game_loss",
  "timestamp": "2024-12-09T12:15:00Z",
  "metadata": {
    "roomId": "diamond_kings_002"
  }
}
```

**Resultado en UI:**
- 🔴 Icono de flecha abajo (rojo)
- **Título:** "Mesa: diamond_kings_002"
- **Fecha:** "Hoy, 12:15"
- **Monto:** -300 (rojo)

---

### 3. Carga Admin (Verde ↑)

```json
{
  "userId": "player_123",
  "type": "credit",
  "amount": 10000,
  "reason": "admin_credit",
  "timestamp": "2024-12-08T10:00:00Z",
  "metadata": {
    "adminId": "admin_001",
    "note": "Bono de bienvenida"
  }
}
```

**Resultado en UI:**
- 🟢 Icono de flecha arriba (verde)
- **Título:** "Carga Admin"
- **Fecha:** "Ayer, 10:00"
- **Monto:** +10000 (verde)

---

### 4. Depósito (Verde ↑)

```json
{
  "userId": "player_123",
  "type": "credit",
  "amount": 5000,
  "reason": "deposit",
  "timestamp": "2024-12-07T18:45:00Z",
  "metadata": {
    "paymentMethod": "credit_card",
    "transactionId": "txn_abc123"
  }
}
```

**Resultado en UI:**
- 🟢 Icono de flecha arriba (verde)
- **Título:** "Depósito"
- **Fecha:** "Viernes, 18:45"
- **Monto:** +5000 (verde)

---

### 5. Retiro (Rojo ↓)

```json
{
  "userId": "player_123",
  "type": "debit",
  "amount": 2000,
  "reason": "withdrawal",
  "timestamp": "2024-11-30T09:30:00Z",
  "metadata": {
    "walletAddress": "0x1234...",
    "network": "ethereum"
  }
}
```

**Resultado en UI:**
- 🔴 Icono de flecha abajo (rojo)
- **Título:** "Retiro"
- **Fecha:** "30/11/2024, 09:30"
- **Monto:** -2000 (rojo)

---

### 6. Entrada a Partida (Rojo ↓)

```json
{
  "userId": "player_123",
  "type": "debit",
  "amount": 100,
  "reason": "game_entry",
  "timestamp": "2024-12-09T16:00:00Z",
  "metadata": {
    "roomId": "spade_queens_003",
    "buyIn": 100
  }
}
```

**Resultado en UI:**
- 🔴 Icono de flecha abajo (rojo)
- **Título:** "Entrada a Partida"
- **Fecha:** "Hoy, 16:00"
- **Monto:** -100 (rojo)

---

## 🎨 Personalización

### Cambiar colores del gradiente dorado

En `wallet_badge.dart`, busca:

```dart
gradient: LinearGradient(
  colors: [
    const Color(0xFFFFD700).withOpacity(0.9), // 👈 Cambia este
    const Color(0xFFB8860B).withOpacity(0.8), // 👈 Y este
    const Color(0xFF8B7500).withOpacity(0.7), // 👈 Y este
  ],
)
```

### Cambiar el límite de transacciones mostradas

En `wallet_detail_view.dart`, busca:

```dart
.limit(100)  // 👈 Cambia este número
```

### Cambiar el tamaño inicial del bottom sheet

En `wallet_detail_view.dart`, busca:

```dart
DraggableScrollableSheet(
  initialChildSize: 0.85,  // 👈 85% de la pantalla
  minChildSize: 0.5,       // 👈 Mínimo 50%
  maxChildSize: 0.95,      // 👈 Máximo 95%
)
```

---

## 🔐 Reglas de Firestore Recomendadas

Para la colección `transaction_logs`:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Transaction Logs - Solo lectura del usuario, escritura solo por Cloud Functions
    match /transaction_logs/{docId} {
      allow read: if request.auth != null 
                  && request.auth.uid == resource.data.userId;
      allow write: if false; // Solo Cloud Functions pueden escribir
    }
  }
}
```

---

## ✅ Checklist de Integración

- [ ] WalletProvider inicializado en main.dart
- [ ] Firebase configurado correctamente
- [ ] Colección `transaction_logs` creada en Firestore
- [ ] Reglas de seguridad configuradas
- [ ] WalletBadge importado en tu pantalla
- [ ] Dependencia `intl` instalada (ya está ✅)
- [ ] Probado en móvil y web
- [ ] Transacciones de prueba creadas en Firestore

---

## 🐛 Debugging

### Ver logs de transacciones en consola

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

// Temporal: Ver todas las transacciones
FirebaseFirestore.instance
  .collection('transaction_logs')
  .where('userId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
  .orderBy('timestamp', descending: true)
  .limit(10)
  .get()
  .then((snapshot) {
    for (var doc in snapshot.docs) {
      print('Transaction: ${doc.data()}');
    }
  });
```

### Crear transacción de prueba manualmente

```dart
// Solo para testing - Normalmente las Cloud Functions hacen esto
FirebaseFirestore.instance.collection('transaction_logs').add({
  'userId': FirebaseAuth.instance.currentUser!.uid,
  'type': 'credit',
  'amount': 1000,
  'reason': 'game_win',
  'timestamp': Timestamp.now(),
  'beforeBalance': 5000,
  'afterBalance': 6000,
  'hash': 'test_hash_123',
  'metadata': {
    'roomId': 'test_room_001',
  },
});
```

---

¡Ahora tienes todo listo para usar el sistema de wallet premium! 🎉

