# 🔗 Integración Opcional: Firebase + Railway

Si quieres que el servidor de poker (Railway) valide créditos antes de permitir jugar, aquí está el código:

## 1. Instalar Firebase Admin en el servidor

```bash
cd e:\Poker\server
npm install firebase-admin
```

## 2. Agregar verificación de Firebase Token

**Archivo: `server/src/middleware/firebaseAuth.ts`**

```typescript
import * as admin from 'firebase-admin';

// Inicializar Firebase Admin (coloca tu serviceAccountKey.json en server/)
admin.initializeApp({
  credential: admin.credential.cert('./serviceAccountKey.json')
});

export async function verifyFirebaseToken(token: string): Promise<string | null> {
  try {
    const decodedToken = await admin.auth().verifyIdToken(token);
    return decodedToken.uid;
  } catch (error) {
    console.error('Error verifying token:', error);
    return null;
  }
}

export async function getUserBalance(uid: string): Promise<number> {
  try {
    const userDoc = await admin.firestore().collection('users').doc(uid).get();
    return userDoc.data()?.walletBalance || 0;
  } catch (error) {
    console.error('Error getting balance:', error);
    return 0;
  }
}

export async function deductCreditsForGame(uid: string, amount: number): Promise<boolean> {
  // Llamar a Cloud Function desde el servidor
  const db = admin.firestore();
  
  try {
    const result = await db.runTransaction(async (transaction) => {
      const userRef = db.collection('users').doc(uid);
      const userDoc = await transaction.get(userRef);
      
      const currentBalance = userDoc.data()?.walletBalance || 0;
      
      if (currentBalance < amount) {
        throw new Error('Insufficient balance');
      }
      
      transaction.update(userRef, {
        walletBalance: currentBalance - amount,
        lastUpdated: admin.firestore.FieldValue.serverTimestamp()
      });
      
      return true;
    });
    
    return result;
  } catch (error) {
    console.error('Error deducting credits:', error);
    return false;
  }
}
```

## 3. Modificar Socket.IO para validar créditos

**Archivo: `server/src/index.ts`**

```typescript
import { verifyFirebaseToken, getUserBalance, deductCreditsForGame } from './middleware/firebaseAuth';

io.on('connection', async (socket) => {
  console.log('New connection:', socket.id);
  
  // Recibir token de Firebase del cliente
  socket.on('authenticate', async (data: { token: string }) => {
    const uid = await verifyFirebaseToken(data.token);
    
    if (!uid) {
      socket.emit('auth_error', { message: 'Invalid token' });
      socket.disconnect();
      return;
    }
    
    // Guardar uid en la socket
    (socket as any).userId = uid;
    socket.emit('authenticated', { uid });
  });
  
  // Al crear/unirse a sala, verificar balance
  socket.on('createRoom', async (data: { name: string, token: string }) => {
    const uid = await verifyFirebaseToken(data.token);
    
    if (!uid) {
      socket.emit('error', { message: 'Not authenticated' });
      return;
    }
    
    // Verificar balance (ej: 100 créditos para entrar)
    const balance = await getUserBalance(uid);
    const entryFee = 100;
    
    if (balance < entryFee) {
      socket.emit('insufficient_balance', {
        required: entryFee,
        current: balance
      });
      return;
    }
    
    // Deducir créditos
    const deducted = await deductCreditsForGame(uid, entryFee);
    
    if (!deducted) {
      socket.emit('error', { message: 'Failed to deduct credits' });
      return;
    }
    
    // Continuar con lógica normal del juego
    const roomId = generateRoomId();
    // ... resto del código
  });
});
```

## 4. Actualizar Flutter para enviar token

**Archivo: `app/lib/services/socket_service.dart`**

```dart
import 'package:firebase_auth/firebase_auth.dart';

class SocketService extends ChangeNotifier {
  // ... código existente
  
  Future<void> connect() async {
    // Obtener token de Firebase
    final user = FirebaseAuth.instance.currentUser;
    String? token;
    
    if (user != null) {
      token = await user.getIdToken();
    }
    
    _socket = io(serverUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
    });
    
    _socket!.onConnect((_) {
      print('Connected to server');
      
      // Autenticar con Firebase token
      if (token != null) {
        _socket!.emit('authenticate', {'token': token});
      }
      
      _isConnected = true;
      notifyListeners();
    });
    
    // Escuchar respuesta de autenticación
    _socket!.on('authenticated', (data) {
      print('Authenticated: ${data['uid']}');
    });
    
    _socket!.on('insufficient_balance', (data) {
      // Mostrar diálogo de saldo insuficiente
      print('Insufficient balance: ${data['required']} required, ${data['current']} available');
    });
  }
  
  Future<void> createRoom(String playerName, {
    required Function(String) onSuccess,
    Function(String)? onError,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken();
    
    _socket!.emit('createRoom', {
      'name': playerName,
      'token': token,
    });
    
    // ... resto del código
  }
}
```

## ¿Cuándo implementar esto?

**Ahora NO es necesario** - el juego funciona independientemente.

**Implementa esto cuando:**
1. Quieras que SOLO jugadores con créditos puedan jugar
2. Quieras cobrar entrada a las mesas
3. Quieras dar premios automáticamente

**Ventajas de hacerlo:**
- ✅ Control total de economía del juego
- ✅ No pueden jugar sin créditos
- ✅ Menos trampa posible

**Desventajas:**
- ⚠️ Requiere configurar service account en Railway
- ⚠️ Añade complejidad al servidor
- ⚠️ Latencia adicional por validación

**Mi recomendación:** Prueba primero el sistema actual (Firebase separado) y luego integra si lo necesitas.
