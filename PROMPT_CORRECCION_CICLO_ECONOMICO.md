# 🔧 PROMPT: Corrección del Ciclo Económico de Antigravity Poker

## 📋 Contexto

El ciclo económico del sistema de poker **NO está funcionando** según la especificación documentada en `README_CICLO_ECONOMICO.md`. El problema principal es que la función `settleGameRound` está haciendo un **cashout parcial después de cada mano ganada**, cuando debería solo actualizar las fichas en la mesa y distribuir el rake, pero **NO transferir dinero a la billetera** hasta el cashout final.

---

## 🚨 PROBLEMA CRÍTICO IDENTIFICADO

### Archivo: `functions/src/functions/gameEconomy.ts`
### Función: `settleGameRound`

**Comportamiento Actual (INCORRECTO):**
- ❌ Después de cada mano ganada, transfiere crédito a la billetera del usuario (línea 277)
- ❌ Limpia `moneyInPlay: 0` y `currentTableId: null` después de cada mano (líneas 278-279)
- ❌ Resetea las fichas del ganador a 0 en la mesa (línea 286)
- ❌ Esto hace que el usuario "cobre" después de cada mano, cuando debería seguir jugando

**Comportamiento Esperado (según README_CICLO_ECONOMICO.md):**
- ✅ Durante el juego, las fichas solo deben moverse en `poker_tables/{tableId}.players[].chips`
- ✅ NO debe transferirse dinero a la billetera hasta el cashout final (`processCashOut`)
- ✅ NO debe limpiarse `moneyInPlay` ni `currentTableId` hasta el cashout final
- ✅ El rake debe calcularse y distribuirse, pero el dinero del usuario debe quedarse en la mesa

---

## 📖 ESPECIFICACIÓN DEL README

Según `README_CICLO_ECONOMICO.md`, el flujo correcto es:

### 2. **JUEGO (Durante la Partida)**
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

**⚠️ IMPORTANTE:** Durante el juego, el usuario NO debe recibir crédito en su billetera. El dinero queda "congelado" en `moneyInPlay` y las fichas se mueven solo en la mesa.

---

## 🔧 CORRECCIONES REQUERIDAS

### 1. **Corregir `settleGameRound` en `functions/src/functions/gameEconomy.ts`**

**ELIMINAR completamente el "Paso 4: CASHOUT / LIQUIDACIÓN"** (líneas 261-298 aproximadamente).

**Lo que DEBE hacer `settleGameRound`:**
1. ✅ Calcular el rake del bote (8% del pot total)
2. ✅ Distribuir el rake según tipo de mesa (Plataforma/Club/Seller)
3. ✅ Actualizar las fichas del ganador en `poker_tables/{tableId}.players[].chips`
4. ✅ Actualizar `poker_sessions/{sessionId}.totalRakePaid` (acumular rake pagado)
5. ✅ Registrar en `financial_ledger` (auditoría de la mano)
6. ✅ Actualizar estadísticas diarias (`stats_daily`)

**Lo que NO DEBE hacer `settleGameRound`:**
- ❌ Transferir crédito a la billetera del usuario
- ❌ Limpiar `moneyInPlay` o `currentTableId`
- ❌ Resetear las fichas del ganador a 0 en la mesa
- ❌ Cerrar la sesión o cambiar su estado

### 2. **Estructura Correcta de `settleGameRound`**

```typescript
export const settleGameRound = async (data: SettleRoundRequest, context: functions.https.CallableContext) => {
    // ... validaciones existentes ...

    // PASO 1: Cálculo del Bote y Rake (EN MEMORIA)
    const totalPot = potTotal;
    const rakeAmount = Math.floor(totalPot * RAKE_PERCENTAGE);
    const winnerPrize = totalPot - rakeAmount; // Premio neto que se lleva el ganador

    // PASO 2: Distribución del Rake según tipo de mesa (ESCRIBIR EN BD)
    // - Plataforma: 50% o 100%
    // - Club: 30% (si pública)
    // - Seller: 20% (si pública)

    // PASO 3: Actualizar Stack del Ganador en la Mesa (ÚNICA FUENTE DE VERDAD)
    // - Leer chips actuales del ganador en poker_tables
    // - Sumar winnerPrize a sus chips
    // - Actualizar poker_tables/{tableId}.players[].chips

    // PASO 4: Actualizar Sesión (solo auditoría)
    // - Incrementar totalRakePaid en poker_sessions
    // - Actualizar currentChips (solo para auditoría, NO fuente de verdad)

    // PASO 5: Registrar en Ledger (auditoría)
    // - Crear registro en financial_ledger con tipo 'GAME_WIN'
    // - Incluir: potTotal, rakeAmount, winnerPrize, chips finales

    // PASO 6: Actualizar Estadísticas Diarias
    // - Incrementar totalVolume, dailyGGR, totalRake en stats_daily

    // ❌ NO HACER:
    // - NO transferir crédito a billetera
    // - NO limpiar moneyInPlay o currentTableId
    // - NO resetear chips a 0 en la mesa
    // - NO cerrar la sesión
};
```

### 3. **Verificar que `processCashOut` sigue siendo la única función que transfiere dinero**

La función `processCashOut` en `functions/src/functions/table.ts` ya está correctamente implementada según el README. Solo debe:
- ✅ Leer fichas de `poker_tables` (fuente de verdad)
- ✅ Calcular rake sobre ganancia bruta
- ✅ Transferir payout a la billetera
- ✅ Limpiar `moneyInPlay: 0` y `currentTableId: null`
- ✅ Cerrar la sesión

---

## ✅ CHECKLIST DE VERIFICACIÓN

Después de aplicar las correcciones, verificar:

- [x] `settleGameRound` NO transfiere crédito a la billetera del usuario ✅ CORREGIDO
- [x] `settleGameRound` NO limpia `moneyInPlay` ni `currentTableId` ✅ CORREGIDO
- [x] `settleGameRound` solo actualiza fichas en `poker_tables/{tableId}.players[].chips` ✅ CORREGIDO
- [x] `settleGameRound` distribuye el rake correctamente (Plataforma/Club/Seller) ✅ MANTENIDO
- [x] `settleGameRound` actualiza `poker_sessions.totalRakePaid` (acumular) ✅ CORREGIDO
- [x] `settleGameRound` registra en `financial_ledger` (auditoría) ✅ CORREGIDO
- [x] `processCashOut` es la ÚNICA función que transfiere dinero a la billetera ✅ VERIFICADO
- [x] `processCashOut` es la ÚNICA función que limpia `moneyInPlay` y `currentTableId` ✅ VERIFICADO
- [x] Durante el juego, el dinero queda "congelado" en `moneyInPlay` ✅ CORREGIDO
- [x] Las fichas se mueven solo en `poker_tables` durante el juego ✅ CORREGIDO

## ✅ CORRECCIONES APLICADAS

**Fecha:** 2024  
**Archivo modificado:** `functions/src/functions/gameEconomy.ts`

### Cambios realizados:

1. **Eliminado el "Paso 4: CASHOUT / LIQUIDACIÓN"** (líneas 261-298):
   - ❌ Eliminada la transferencia de crédito a la billetera del usuario
   - ❌ Eliminada la limpieza de `moneyInPlay` y `currentTableId`
   - ❌ Eliminado el reseteo de fichas a 0 en la mesa

2. **Reemplazado por "Paso 4: ACTUALIZAR SESIÓN (SOLO AUDITORÍA)"**:
   - ✅ Solo actualiza `poker_sessions.currentChips` (auditoría)
   - ✅ Acumula `totalRakePaid` en la sesión
   - ✅ NO modifica la billetera del usuario

3. **Actualizado el "Paso 5: HISTORIAL (LEDGER)"**:
   - ✅ Eliminado campo `totalCashedOut` (ya no hay cashout)
   - ✅ Agregado campo `finalChips` para registrar fichas finales
   - ✅ Actualizada descripción para indicar que las fichas quedan en la mesa

4. **Actualizado el comentario del algoritmo**:
   - ✅ Documentación actualizada para reflejar el comportamiento correcto
   - ✅ Agregadas advertencias sobre lo que NO debe hacer la función

---

## 📝 NOTAS ADICIONALES

1. **Flujo Correcto del Dinero:**
   - **Entrada:** `joinTable` → Descuenta de `credit`, aumenta `moneyInPlay`
   - **Durante Juego:** `settleGameRound` → Solo mueve fichas en mesa, distribuye rake
   - **Salida:** `processCashOut` → Calcula rake final, transfiere a `credit`, limpia estado

2. **Fuente de Verdad:**
   - Las fichas del usuario son las que tiene en `poker_tables/{tableId}.players[].chips`
   - `poker_sessions.currentChips` es solo para auditoría
   - `moneyInPlay` indica cuánto dinero está "congelado" en juego

3. **Rake:**
   - Se calcula sobre la **ganancia bruta** (GrossProfit = FichasFinales - BuyIn)
   - Durante el juego: se distribuye pero NO se cobra al usuario (se acumula en sesión)
   - Al cashout: se calcula el rake total y se cobra una sola vez

---

## 🎯 RESULTADO ESPERADO

Después de aplicar las correcciones:

1. Un usuario puede jugar múltiples manos sin que se le transfiera dinero a su billetera
2. Las fichas se actualizan correctamente en `poker_tables` después de cada mano
3. El rake se distribuye correctamente después de cada mano ganada
4. El usuario solo recibe dinero en su billetera cuando hace `processCashOut`
5. El estado (`moneyInPlay`, `currentTableId`) solo se limpia en el cashout final

---

**Prioridad:** CRÍTICA - El ciclo económico actual está roto y permite que los usuarios "cobren" después de cada mano en lugar de al finalizar la sesión.

