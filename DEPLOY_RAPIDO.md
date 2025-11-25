# 🚀 Pasos Rápidos de Deploy - Firebase Auth & Credits

> **Nota**: Ya tienes Firebase configurado y experiencia con web deploys, así que este proceso será directo.

## ⚡ Deploy Rápido (5 pasos)

### 1. Instalar Dependencias de Flutter

```bash
cd e:\Poker\app
flutter pub get
```

### 2. Configurar Firebase para Flutter

```bash
# Si no tienes flutterfire_cli instalado
dart pub global activate flutterfire_cli

# Configurar Firebase (esto crea firebase_options.dart automáticamente)
flutterfire configure
```

**Selecciona:**
- Tu proyecto Firebase existente
- Plataformas: Web, Android, iOS (las que necesites)

### 3. Deploy Cloud Functions

```bash
cd e:\Poker\functions
npm install
npm run build
firebase deploy --only functions
```

**Funciones que se deployarán:**
- `addCreditsFunction` - Agregar créditos
- `deductCreditsFunction` - Deducir créditos

### 4. Deploy Firestore Security Rules

```bash
cd e:\Poker\app
firebase deploy --only firestore:rules
```

### 5. Habilitar Auth Providers en Console

1. Ve a: https://console.firebase.google.com
2. **Authentication** → **Sign-in method**
3. Habilita:
   - ✅ **Email/Password**
   - ✅ **Google** (agrega tu email de soporte)

---

## 🧪 Probar Localmente

```bash
cd e:\Poker\app
flutter run -d chrome
```

**Flujo de prueba:**
1. Registra un usuario nuevo
2. Agrega créditos (botón "Agregar" en lobby)
3. Verifica balance en tiempo real

---

## 📊 Verificar en Firebase Console

1. **Authentication**: Ver usuarios registrados
2. **Firestore**: Ver colecciones `users` y `transaction_logs`
3. **Functions**: Ver logs de invocaciones

---

## 🔧 Solo si hay problemas

### Error: Firebase not initialized

```bash
# Re-configurar Firebase
cd e:\Poker\app
flutterfire configure
```

### Error: Functions deployment fails

```bash
# Verificar que estás en el proyecto correcto
firebase projects:list
firebase use <tu-proyecto-id>
```

### Error: Google Sign-In no funciona

1. Ve a Firebase Console → Project Settings → Your apps
2. Descarga `google-services.json` actualizado (Android)
3. Colócalo en `e:\Poker\app\android\app\`

---

## 📝 Integración con el Juego

Para deducir créditos al entrar a una mesa, agrega esto donde creas/unes salas:

```dart
// Antes de socketService.createRoom() o joinRoom()
final walletProvider = context.read<WalletProvider>();
const entryFee = 100.0;

if (walletProvider.balance < entryFee) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Saldo insuficiente. Necesitas $entryFee créditos')),
  );
  return;
}

final success = await walletProvider.deductCredits(
  entryFee,
  'game_entry',
  metadata: {'roomId': roomId},
);

if (success) {
  // Continuar al juego
  socketService.createRoom(...);
}
```

---

## 🎯 ¿Ya tienes todo deployado?

Si ya hiciste los pasos 1-5, solo necesitas:

```bash
cd e:\Poker\app
flutter run -d chrome
```

Y probar el login/registro + sistema de créditos.

---

## 🆘 Ayuda Rápida

- Ver logs de Cloud Functions: `firebase functions:log`
- Ver usuarios: Firebase Console → Authentication
- Ver transacciones: Firebase Console → Firestore → transaction_logs
