# 📊 Documentación Técnica: Ciclo Económico de Antigravity Poker

## 🎯 Objetivo

Este documento explica el flujo completo del dinero en el sistema de poker, desde la entrada del usuario hasta la salida con distribución exacta del rake. El sistema funciona como un reloj suizo: **Entrada Única → Juego → Salida Única con Distribución Exacta**.

---

## 💰 Flujo del Dinero: ¿De dónde sale? ¿Por dónde pasa? ¿Dónde termina?

### 1. **ENTRADA (Join Table)**

**Origen del Dinero:**
- El dinero sale de la **billetera del usuario** (`users/{uid}.credit`)
- Se descuenta el `buyInAmount` al momento de unirse a la mesa

**Proceso:**
```
Usuario (credit: 10000)
    ↓
joinTable() → Descuenta buyInAmount (ej: 1000)
    ↓
Usuario (credit: 9000, moneyInPlay: 1000, currentTableId: "table123")
    ↓
poker_sessions/{sessionId} → Creada con status: 'active'
```

**Reglas Inquebrantables:**
- ✅ Un usuario **NUNCA** puede tener más de 1 sesión activa por mesa
- ✅ Si existe sesión activa, se retorna esa (idempotencia)
- ✅ Se rechaza `roomId === 'new_room'` o roomId inválido

**Colecciones Afectadas:**
- `users/{uid}`: `credit` disminuye, `moneyInPlay` aumenta, `currentTableId` se establece
- `poker_sessions/{sessionId}`: Nueva sesión creada con `status: 'active'`
- `transaction_logs`: Registro de débito

---

### 2. **JUEGO (Durante la Partida)**

**Flujo del Dinero:**
- El dinero está "congelado" en `moneyInPlay` del usuario
- Las fichas se mueven dentro de `poker_tables/{tableId}.players[].chips`
- **Fuente de Verdad:** Las fichas del usuario son las que tiene en `poker_tables`, NO en `poker_sessions`

**Proceso:**
```
Usuario tiene 1000 fichas en la mesa
    ↓
Juega una mano, apuesta 200
    ↓
Usuario tiene 800 fichas en poker_tables/{tableId}.players[].chips
    ↓
Gana un bote de 500 fichas
    ↓
settleGameRound() → Calcula rake, distribuye, actualiza stack
    ↓
Usuario tiene 1300 fichas en poker_tables/{tableId}.players[].chips
```

**Reglas Inquebrantables:**
- ✅ Las fichas en `poker_tables` son la **ÚNICA fuente de verdad**
- ✅ `poker_sessions.currentChips` es solo para auditoría, NO para cálculos financieros
- ✅ El rake se calcula sobre la **ganancia bruta** (GrossProfit = FichasFinales - BuyIn)

**Distribución del Rake (settleGameRound):**
- **Mesa Privada:** 100% del rake → `system_stats/economy.accumulated_rake`
- **Mesa Pública:** 
  - 50% → `system_stats/economy.accumulated_rake` (Plataforma)
  - 30% → `clubs/{clubId}.walletBalance` (Club Owner)
  - 20% → `users/{sellerId}.credit` (Seller)

**Colecciones Afectadas:**
- `poker_tables/{tableId}.players[].chips`: Fichas actualizadas en tiempo real
- `poker_sessions/{sessionId}.totalRakePaid`: Acumula rake pagado (auditoría)
- `system_stats/economy.accumulated_rake`: Rake de plataforma
- `clubs/{clubId}.walletBalance`: Rake de club (si aplica)
- `users/{sellerId}.credit`: Rake de seller (si aplica)
- `financial_ledger`: Registro de cada mano ganada

---

### 3. **SALIDA (Cash Out)**

**Destino del Dinero:**
- El dinero vuelve a la **billetera del usuario** (`users/{uid}.credit`)
- Se calcula el `payout` = FichasFinales - Rake
- Se limpia el estado: `moneyInPlay: 0`, `currentTableId: null`

**Proceso:**
```
Usuario tiene 1500 fichas en poker_tables/{tableId}.players[].chips
    ↓
processCashOut() → Lee fichas de la mesa (FUENTE DE VERDAD)
    ↓
Cálculo:
  - BuyInOriginal: 1000 (de poker_sessions)
  - FichasFinales: 1500 (de poker_tables)
  - GrossProfit: 1500 - 1000 = 500
  - Rake: 500 * 0.08 = 40
  - Payout: 1500 - 40 = 1460
    ↓
Distribución del Rake:
  - Plataforma: 20 (50% si pública, 100% si privada)
  - Club: 12 (30% si pública)
  - Seller: 8 (20% si pública)
    ↓
Usuario (credit: 10460, moneyInPlay: 0, currentTableId: null)
    ↓
poker_sessions/{sessionId} → status: 'completed'
```

**Reglas Inquebrantables:**
- ✅ **NUNCA** crear una nueva sesión al hacer cashout
- ✅ Las fichas se leen de `poker_tables`, NO de `poker_sessions`
- ✅ Si el jugador no está en la mesa y no se proporcionan fichas, ERROR
- ✅ **LIMPIEZA OBLIGATORIA:** `moneyInPlay: 0`, `currentTableId: null`

**Colecciones Afectadas:**
- `users/{uid}`: `credit` aumenta, `moneyInPlay: 0`, `currentTableId: null`
- `poker_sessions/{sessionId}`: `status: 'completed'`, `netResult`, `exitFee`
- `poker_tables/{tableId}.players[].chips`: Se establece a 0
- `system_stats/economy.accumulated_rake`: Rake de plataforma
- `clubs/{clubId}.walletBalance`: Rake de club (si aplica)
- `users/{sellerId}.credit`: Rake de seller (si aplica)
- `financial_ledger`: Registro de cashout
- `transaction_logs`: Registro de crédito

---

## 📚 Diccionario de Datos

### Campos Financieros en `poker_sessions`

| Campo | Tipo | Descripción | Ejemplo |
|-------|------|-------------|---------|
| `buyInAmount` | `number` | Monto original que el usuario pagó para entrar | `1000` |
| `currentChips` | `number` | Fichas actuales (solo auditoría, NO fuente de verdad) | `1500` |
| `totalRakePaid` | `number` | Rake total pagado durante la sesión | `40` |
| `netResult` | `number` | Ganancia/pérdida neta = FichasFinales - BuyInOriginal | `500` (puede ser negativo) |
| `exitFee` | `number` | Rake cobrado al salir (igual a `totalRakePaid` si solo hay un cashout) | `40` |
| `status` | `'active' \| 'completed'` | Estado de la sesión | `'active'` |

**⚠️ IMPORTANTE:** 
- `currentChips` en `poker_sessions` es solo para auditoría
- La **fuente de verdad** son las fichas en `poker_tables/{tableId}.players[].chips`

---

### Campos Financieros en `financial_ledger`

| Campo | Tipo | Descripción | Ejemplo |
|-------|------|-------------|---------|
| `type` | `'GAME_WIN' \| 'GAME_LOSS' \| 'SESSION_END' \| 'RAKE_COLLECTED'` | Tipo de transacción | `'GAME_WIN'` |
| `amount` | `number` | Monto neto (puede ser positivo o negativo) | `500` |
| `netAmount` | `number` | Lo que realmente recibió el usuario (después del rake) | `1460` |
| `netProfit` | `number` | Ganancia/pérdida neta = GrossProfit | `500` |
| `grossAmount` | `number` | Fichas finales (fuente de verdad) | `1500` |
| `rakePaid` | `number` | Rake cobrado | `40` |
| `buyInAmount` | `number` | Monto original del buy-in | `1000` |

**Fórmulas:**
- `netProfit = grossAmount - buyInAmount`
- `rakePaid = netProfit > 0 ? Math.floor(netProfit * 0.08) : 0`
- `netAmount = grossAmount - rakePaid`

---

### Campos Financieros en `users`

| Campo | Tipo | Descripción | Ejemplo |
|-------|------|-------------|---------|
| `credit` | `number` | Billetera del usuario (dinero disponible) | `10000` |
| `moneyInPlay` | `number` | Dinero congelado en juego (debe ser 0 al salir) | `0` |
| `currentTableId` | `string \| null` | ID de la mesa actual (debe ser null al salir) | `null` |

**Reglas:**
- `moneyInPlay` debe ser `0` cuando el usuario no está jugando
- `currentTableId` debe ser `null` cuando el usuario no está jugando
- Al hacer cashout, ambos campos se limpian **obligatoriamente**

---

### Campos Financieros en `system_stats/economy`

| Campo | Tipo | Descripción | Ejemplo |
|-------|------|-------------|---------|
| `accumulated_rake` | `number` | Rake total acumulado de la plataforma | `50000` |

**Distribución:**
- En mesas privadas: 100% del rake va aquí
- En mesas públicas: 50% del rake va aquí

---

### Campos Financieros en `clubs`

| Campo | Tipo | Descripción | Ejemplo |
|-------|------|-------------|---------|
| `walletBalance` | `number` | Billetera del club (rake recibido) | `5000` |

**Distribución:**
- En mesas públicas: 30% del rake va aquí (si el usuario pertenece a un club)

---

## 🔄 Resumen del Ciclo Completo

```
1. ENTRADA (joinTable)
   Usuario: credit -= buyInAmount
   Usuario: moneyInPlay = buyInAmount
   Usuario: currentTableId = tableId
   Sesión: status = 'active'

2. JUEGO (settleGameRound)
   Mesa: players[].chips se actualiza
   Rake: Se calcula y distribuye
   Plataforma: accumulated_rake += rake (50% o 100%)
   Club: walletBalance += rake (30% si pública)
   Seller: credit += rake (20% si pública)

3. SALIDA (processCashOut)
   Usuario: credit += payout (FichasFinales - Rake)
   Usuario: moneyInPlay = 0 ✅
   Usuario: currentTableId = null ✅
   Sesión: status = 'completed'
   Mesa: players[].chips = 0
```

---

## ⚠️ Reglas Inquebrantables

1. **Idempotencia en Entrada:** Un usuario NUNCA puede tener más de 1 sesión activa por mesa
2. **Fuente de Verdad en Salida:** Las fichas del usuario son las que tiene en `poker_tables`, NO en `poker_sessions`
3. **Distribución del Rake:**
   - Privada: 100% Plataforma
   - Pública: 50% Plataforma / 30% Club / 20% Seller
4. **Limpieza de Estado:** Siempre, sin excepción, `moneyInPlay: 0` y `currentTableId: null` al finalizar

---

## 🛠️ Funciones Principales

### `joinTable(data, context)`
- **Propósito:** Entrada del usuario a la mesa
- **Regla:** Idempotencia estricta (máximo 1 sesión activa por mesa)
- **Colecciones:** `users`, `poker_sessions`, `transaction_logs`

### `settleGameRound(data, context)`
- **Propósito:** Liquidar una mano ganada
- **Regla:** Distribución del rake según tipo de mesa
- **Colecciones:** `poker_tables`, `poker_sessions`, `system_stats`, `clubs`, `users`, `financial_ledger`

### `processCashOut(data, context)`
- **Propósito:** Salida del usuario de la mesa
- **Regla:** Fuente de verdad en `poker_tables`, nunca crear sesiones nuevas
- **Colecciones:** `users`, `poker_sessions`, `poker_tables`, `system_stats`, `clubs`, `users`, `financial_ledger`, `transaction_logs`

---

## 📝 Notas Técnicas

- Todas las operaciones financieras se realizan en **transacciones atómicas** de Firestore
- El rake se calcula sobre la **ganancia bruta** (GrossProfit), NO sobre el stack total
- Las sesiones (`poker_sessions`) son solo para **auditoría de tiempo**, no para cálculos financieros
- La **fuente de verdad** para las fichas del usuario es siempre `poker_tables/{tableId}.players[].chips`

---

**Última actualización:** 2025
**Versión:** 1.0.0

