# 🎨 Guía de Personalización - Wallet Premium

## 🎯 Personalizar Colores

### 1. Cambiar el Esquema Dorado por Platino

En `wallet_badge.dart`, línea ~79:

**Actual (Dorado):**
```dart
gradient: LinearGradient(
  colors: [
    const Color(0xFFFFD700).withOpacity(0.9), // Oro brillante
    const Color(0xFFB8860B).withOpacity(0.8), // Oro oscuro
    const Color(0xFF8B7500).withOpacity(0.7), // Oro profundo
  ],
)
```

**Cambiar a Platino:**
```dart
gradient: LinearGradient(
  colors: [
    const Color(0xFFE5E4E2).withOpacity(0.9), // Platino claro
    const Color(0xFFC0C0C0).withOpacity(0.8), // Plata
    const Color(0xFF8C8C8C).withOpacity(0.7), // Gris metálico
  ],
)
```

**Cambiar a Bronce:**
```dart
gradient: LinearGradient(
  colors: [
    const Color(0xFFCD7F32).withOpacity(0.9), // Bronce brillante
    const Color(0xFFB87333).withOpacity(0.8), // Bronce medio
    const Color(0xFF8B4513).withOpacity(0.7), // Bronce oscuro
  ],
)
```

**Cambiar a Diamante (Azul Brillante):**
```dart
gradient: LinearGradient(
  colors: [
    const Color(0xFF00D4FF).withOpacity(0.9), // Cian brillante
    const Color(0xFF0080FF).withOpacity(0.8), // Azul medio
    const Color(0xFF004080).withOpacity(0.7), // Azul oscuro
  ],
)
```

---

### 2. Cambiar Color del Saldo "En Mesa"

En `wallet_badge.dart`, línea ~159:

**Actual (Verde Neón):**
```dart
color: const Color(0xFF00FF88).withOpacity(0.9),
```

**Opciones:**
```dart
// Amarillo brillante
color: const Color(0xFFFFD700).withOpacity(0.9),

// Naranja neón
color: const Color(0xFFFF6600).withOpacity(0.9),

// Púrpura neón
color: const Color(0xFFBF00FF).withOpacity(0.9),

// Azul eléctrico
color: const Color(0xFF00BFFF).withOpacity(0.9),
```

---

### 3. Cambiar Colores de Transacciones

En `wallet_detail_view.dart`, línea ~346:

**Ganancias (Actual: Verde):**
```dart
iconColor = const Color(0xFF00FF88);
```

**Opciones:**
```dart
// Dorado
iconColor = const Color(0xFFFFD700);

// Azul brillante
iconColor = const Color(0xFF00D4FF);

// Verde esmeralda
iconColor = const Color(0xFF50C878);
```

**Pérdidas (Actual: Rojo):**
```dart
iconColor = const Color(0xFFFF4444);
```

**Opciones:**
```dart
// Naranja
iconColor = const Color(0xFFFF8800);

// Rojo oscuro
iconColor = const Color(0xFFCC0000);

// Púrpura
iconColor = const Color(0xFF9933CC);
```

---

## 🖼️ Personalizar Iconografía

### 1. Cambiar Icono de Billetera

En `wallet_badge.dart`, línea ~124:

**Actual:**
```dart
icon: Icons.account_balance_wallet_rounded,
```

**Opciones:**
```dart
// Cofre del tesoro
icon: Icons.redeem_rounded,

// Diamante
icon: Icons.diamond_rounded,

// Estrella (premium)
icon: Icons.star_rounded,

// Fichas de poker
icon: Icons.casino_rounded,

// Monedas apiladas
icon: Icons.toll_rounded,

// Corona (VIP)
icon: Icons.emoji_events_rounded,
```

---

### 2. Cambiar Iconos de Transacciones

En `wallet_detail_view.dart`, líneas ~344-362:

**Ganancias (Actual: Flecha Arriba):**
```dart
icon = Icons.arrow_upward_rounded;
```

**Opciones:**
```dart
// Pulgar arriba
icon = Icons.thumb_up_rounded;

// Estrella
icon = Icons.star_rounded;

// Signo +
icon = Icons.add_circle_rounded;

// Trofeo
icon = Icons.emoji_events_rounded;
```

**Pérdidas (Actual: Flecha Abajo):**
```dart
icon = Icons.arrow_downward_rounded;
```

**Opciones:**
```dart
// Pulgar abajo
icon = Icons.thumb_down_rounded;

// Signo -
icon = Icons.remove_circle_rounded;

// X
icon = Icons.cancel_rounded;

// Tendencia bajista
icon = Icons.trending_down_rounded;
```

---

## 📏 Personalizar Tamaños

### 1. Tamaño del Badge

En `wallet_badge.dart`, línea ~75:

**Actual:**
```dart
padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
```

**Más Grande:**
```dart
padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
```

**Más Pequeño:**
```dart
padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
```

---

### 2. Tamaño de Texto del Saldo

En `wallet_badge.dart`, línea ~145:

**Actual:**
```dart
fontSize: 18,
```

**Más Grande (para destacar):**
```dart
fontSize: 24,
```

**Más Pequeño (para compacto):**
```dart
fontSize: 14,
```

---

### 3. Tamaño del Bottom Sheet

En `wallet_detail_view.dart`, línea ~16:

**Actual:**
```dart
DraggableScrollableSheet(
  initialChildSize: 0.85,  // 85% de pantalla
  minChildSize: 0.5,       // Mínimo 50%
  maxChildSize: 0.95,      // Máximo 95%
)
```

**Más Grande:**
```dart
initialChildSize: 0.95,  // 95%
minChildSize: 0.7,       // 70%
maxChildSize: 1.0,       // 100%
```

**Más Pequeño:**
```dart
initialChildSize: 0.6,   // 60%
minChildSize: 0.3,       // 30%
maxChildSize: 0.8,       // 80%
```

---

## ✨ Efectos Visuales

### 1. Aumentar/Reducir Blur (Glassmorphism)

En `wallet_badge.dart`, línea ~98:

**Actual:**
```dart
filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
```

**Más Borroso (efecto intenso):**
```dart
filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
```

**Menos Borroso (más nítido):**
```dart
filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
```

---

### 2. Cambiar Intensidad de Sombras

En `wallet_badge.dart`, línea ~83:

**Actual:**
```dart
boxShadow: [
  BoxShadow(
    color: const Color(0xFFFFD700).withOpacity(0.4),
    blurRadius: 12,
    spreadRadius: 2,
  ),
]
```

**Sombra Más Intensa:**
```dart
boxShadow: [
  BoxShadow(
    color: const Color(0xFFFFD700).withOpacity(0.7), // +opacidad
    blurRadius: 20,                                   // +blur
    spreadRadius: 5,                                  // +spread
  ),
]
```

**Sombra Sutil:**
```dart
boxShadow: [
  BoxShadow(
    color: const Color(0xFFFFD700).withOpacity(0.2),
    blurRadius: 6,
    spreadRadius: 1,
  ),
]
```

---

### 3. Cambiar Velocidad de Animación

En `wallet_badge.dart`, línea ~27:

**Actual (150ms):**
```dart
_controller = AnimationController(
  duration: const Duration(milliseconds: 150),
  vsync: this,
);
```

**Más Rápida (snappy):**
```dart
duration: const Duration(milliseconds: 100),
```

**Más Lenta (suave):**
```dart
duration: const Duration(milliseconds: 250),
```

---

### 4. Cambiar Escala de Presión

En `wallet_badge.dart`, línea ~29:

**Actual (95%):**
```dart
_scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(...)
```

**Presión Más Pronunciada:**
```dart
_scaleAnimation = Tween<double>(begin: 1.0, end: 0.90).animate(...)
```

**Presión Sutil:**
```dart
_scaleAnimation = Tween<double>(begin: 1.0, end: 0.98).animate(...)
```

---

## 🔤 Personalizar Tipografía

### 1. Cambiar Fuente del Saldo

En `wallet_badge.dart`, línea ~149:

**Actual (RobotoMono):**
```dart
fontFamily: 'RobotoMono',
```

**Opciones:**
```dart
// Fuente más tecnológica
fontFamily: 'Courier',

// Fuente más elegante
fontFamily: 'Georgia',

// Usar Google Fonts (instala el paquete)
import 'package:google_fonts/google_fonts.dart';

style: GoogleFonts.orbitron(  // Futurista
  color: Colors.white,
  fontSize: 18,
  fontWeight: FontWeight.bold,
),

style: GoogleFonts.rajdhani(  // Moderna
  color: Colors.white,
  fontSize: 18,
  fontWeight: FontWeight.bold,
),
```

---

### 2. Cambiar Letter Spacing

En `wallet_badge.dart`, línea ~151:

**Actual:**
```dart
letterSpacing: 1.2,
```

**Más Espaciado (elegante):**
```dart
letterSpacing: 2.0,
```

**Más Compacto:**
```dart
letterSpacing: 0.5,
```

---

## 📱 Adaptar para Web/Desktop

### 1. Cambiar Bottom Sheet a Dialog (Web)

En `wallet_badge.dart`, línea ~44:

**Actual (siempre bottom sheet):**
```dart
void _openWalletDetail(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const WalletDetailView(),
  );
}
```

**Responsive (móvil: bottom sheet, web: dialog):**
```dart
import 'package:flutter/foundation.dart' show kIsWeb;

void _openWalletDetail(BuildContext context) {
  if (kIsWeb || MediaQuery.of(context).size.width > 800) {
    // Web/Desktop: Dialog centrado
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 500,
          height: 700,
          child: const WalletDetailView(),
        ),
      ),
    );
  } else {
    // Móvil: Bottom sheet
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const WalletDetailView(),
    );
  }
}
```

---

## 🌍 Personalizar Idiomas

### 1. Cambiar Texto "En Mesa"

En `wallet_badge.dart`, línea ~160:

**Actual (Español):**
```dart
'(+${inGameBalance.toStringAsFixed(0)} en mesa)',
```

**Inglés:**
```dart
'(+${inGameBalance.toStringAsFixed(0)} in play)',
```

**Portugués:**
```dart
'(+${inGameBalance.toStringAsFixed(0)} na mesa)',
```

---

### 2. Internacionalización Completa

**Crear archivo `l10n/wallet_strings.dart`:**

```dart
class WalletStrings {
  static String inPlay(String locale) {
    switch (locale) {
      case 'en':
        return 'in play';
      case 'pt':
        return 'na mesa';
      case 'es':
      default:
        return 'en mesa';
    }
  }

  static String myWallet(String locale) {
    switch (locale) {
      case 'en':
        return 'My Wallet';
      case 'pt':
        return 'Minha Carteira';
      case 'es':
      default:
        return 'Mi Billetera';
    }
  }

  static String totalBalance(String locale) {
    switch (locale) {
      case 'en':
        return 'Total Balance';
      case 'pt':
        return 'Saldo Total';
      case 'es':
      default:
        return 'Saldo Total';
    }
  }
}
```

**Usar en el widget:**
```dart
final locale = Localizations.localeOf(context).languageCode;

Text(
  '(+${inGameBalance.toStringAsFixed(0)} ${WalletStrings.inPlay(locale)})',
  ...
)
```

---

## 🎭 Temas Predefinidos

### Tema 1: "Royal Gold" (Actual)
```dart
// Dorado brillante, elegante, premium
primaryColor: Color(0xFFFFD700)
accentColor: Color(0xFF00FF88)
```

### Tema 2: "Midnight Diamond"
```dart
// Azul/platino, futurista, tecnológico
gradient: LinearGradient(
  colors: [
    Color(0xFF00D4FF).withOpacity(0.9),
    Color(0xFF0080FF).withOpacity(0.8),
    Color(0xFF004080).withOpacity(0.7),
  ],
)
// Saldo en mesa: Color(0xFFFFD700) // Dorado
```

### Tema 3: "Emerald Royale"
```dart
// Verde esmeralda, elegante, natural
gradient: LinearGradient(
  colors: [
    Color(0xFF50C878).withOpacity(0.9),
    Color(0xFF2E8B57).withOpacity(0.8),
    Color(0xFF1B5E36).withOpacity(0.7),
  ],
)
// Saldo en mesa: Color(0xFFFFD700)
```

### Tema 4: "Crimson Luxury"
```dart
// Rojo/vino, lujoso, intenso
gradient: LinearGradient(
  colors: [
    Color(0xFFDC143C).withOpacity(0.9),
    Color(0xFF8B0000).withOpacity(0.8),
    Color(0xFF5C0000).withOpacity(0.7),
  ],
)
// Saldo en mesa: Color(0xFFFFD700)
```

---

## 🔧 Personalización Avanzada

### 1. Agregar Partículas Flotantes

```dart
// En wallet_badge.dart, dentro del Stack
Stack(
  children: [
    // Badge actual
    Container(...),
    
    // Partículas doradas flotantes
    Positioned.fill(
      child: CustomPaint(
        painter: GoldParticlesPainter(),
      ),
    ),
  ],
)

class GoldParticlesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Color(0xFFFFD700).withOpacity(0.3)
      ..style = PaintingStyle.fill;
    
    // Dibuja partículas aleatorias
    for (int i = 0; i < 10; i++) {
      canvas.drawCircle(
        Offset(Random().nextDouble() * size.width, Random().nextDouble() * size.height),
        2,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
```

---

### 2. Agregar Haptic Feedback

```dart
import 'package:flutter/services.dart';

void _openWalletDetail(BuildContext context) {
  HapticFeedback.lightImpact(); // Vibración sutil
  
  showModalBottomSheet(...);
}
```

---

### 3. Agregar Sonido

```dart
import 'package:audioplayers/audioplayers.dart';

final AudioPlayer _audioPlayer = AudioPlayer();

void _openWalletDetail(BuildContext context) {
  _audioPlayer.play(AssetSource('sounds/coin.mp3'));
  
  showModalBottomSheet(...);
}
```

---

## 📊 Personalizar Formato de Números

### 1. Separadores de Miles

En `wallet_badge.dart`, línea ~147:

**Actual (sin separadores):**
```dart
balance.toStringAsFixed(0)  // 10000
```

**Con separadores:**
```dart
import 'package:intl/intl.dart';

final formatter = NumberFormat('#,###', 'es');
formatter.format(balance)  // 10,000
```

---

### 2. Mostrar Decimales

**Actual (sin decimales):**
```dart
balance.toStringAsFixed(0)
```

**Con 2 decimales:**
```dart
balance.toStringAsFixed(2)  // 1000.50
```

---

## 🎉 Combinaciones Recomendadas

### Combinación 1: "VIP Gold"
- Gradiente: Royal Gold
- Icono: Corona (emoji_events_rounded)
- Tamaño: Grande (24px)
- Sombras: Intensas
- Animación: Rápida (100ms)

### Combinación 2: "Stealth Diamond"
- Gradiente: Midnight Diamond
- Icono: Diamante (diamond_rounded)
- Tamaño: Medio (18px)
- Sombras: Sutiles
- Animación: Suave (250ms)

### Combinación 3: "Casino Classic"
- Gradiente: Crimson Luxury
- Icono: Fichas (casino_rounded)
- Tamaño: Grande (22px)
- Sombras: Medias
- Animación: Normal (150ms)

---

¡Personaliza tu wallet y hazlo único para tu app! 🎨✨

