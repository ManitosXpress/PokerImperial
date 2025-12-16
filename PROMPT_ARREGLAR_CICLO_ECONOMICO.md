# 🔧 PROMPT: Arreglar Ciclo Económico de Poker

## 📋 CONTEXTO

El sistema de poker tiene problemas en el ciclo económico que no coinciden con la documentación en `README_CICLO_ECONOMICO.md`. Las imágenes muestran que:
- Los balances no se calculan correctamente
- Aparecen transacciones con tipo `GAME_LOSS` que deben ser `SESSION_CLOSE` o `SESSION_END`
- Se están creando sesiones duplicadas
- La economía no refleja correctamente el flujo de dinero

## 🎯 OBJETIVO

Asegurar que el código funcione **EXACTAMENTE** como dice `README_CICLO_ECONOMICO.md`:
1. **Entrada Única**: Un usuario NUNCA puede tener más de 1 sesión activa por mesa
2. **Juego**: Las fichas se mueven solo en `poker_tables`, NO se transfiere dinero a billetera
3. **Salida Única**: Solo `processCashOut` transfiere dinero y limpia estado
4. **Tipos de Transacción**: Cambiar `GAME_LOSS` por `SESSION_CLOSE` o `SESSION_END`

---

## 🔍 PROBLEMAS IDENTIFICADOS

### 1. **Tipo de Transacción Incorrecto: `GAME_LOSS`**

**Archivos afectados:**
- `server/src/middleware/firebaseAuth.ts` (línea 317)
- `functions/src/functions/table.ts` (líneas 1486, posiblemente otras)

**Problema:** Se usa `GAME_LOSS` cuando debería ser `SESSION_CLOSE` o `SESSION_END` para el cierre de sesión.

**Solución:** 
- Reemplazar TODAS las instancias de `GAME_LOSS` por `SESSION_CLOSE` o `SESSION_END` en el contexto de cierre de sesión
- Mantener `GAME_WIN` solo si es necesario para manos individuales (pero según el README, el cierre debe ser `SESSION_END`)

### 2. **Sesiones Duplicadas**

**Archivo:** `functions/src/functions/table.ts` - función `joinTable`

**Problema:** A pesar de tener lógica de idempotencia, pueden crearse sesiones duplicadas en condiciones de carrera.

**Solución:**
- Verificar que la lógica de idempotencia en `joinTable` sea robusta
- Asegurar que la verificación de sesión existente se haga DENTRO de la transacción también
- Agregar logs más detallados para detectar duplicados

### 3. **Economía No Funciona Correctamente**

**Problemas potenciales:**
- El cálculo del rake puede estar mal
- La distribución del rake puede no estar funcionando
- Los balances pueden no actualizarse correctamente

**Archivos a revisar:**
- `functions/src/functions/table.ts` - `processCashOut`
- `functions/src/functions/gameEconomy.ts` - `settleGameRound`
- `server/src/middleware/firebaseAuth.ts` - `endPokerSession`

---

## ✅ TAREAS ESPECÍFICAS

### TAREA 1: Cambiar `GAME_LOSS` por `SESSION_CLOSE` o `SESSION_END`

**Archivo: `server/src/middleware/firebaseAuth.ts`**

**Línea 317:** Cambiar:
```typescript
const ledgerType = netWinnings > buyInAmount ? 'GAME_WIN' : 'GAME_LOSS';
```

Por:
```typescript
const ledgerType = 'SESSION_CLOSE'; // Siempre SESSION_CLOSE para cierre de sesión
```

**Línea 395-409:** Actualizar el registro en `financial_ledger` para usar `SESSION_CLOSE`:
```typescript
transaction.set(ledgerRef, {
    type: 'SESSION_CLOSE', // Cambiar de ledgerType a 'SESSION_CLOSE'
    // ... resto del código
});
```

**Archivo: `functions/src/functions/table.ts`**

**Línea 1486:** Buscar y cambiar cualquier uso de `GAME_LOSS` por `SESSION_CLOSE` o `SESSION_END` (según el contexto).

**Verificar:** Buscar TODAS las instancias de `GAME_LOSS` en el código y reemplazarlas por `SESSION_CLOSE` o `SESSION_END` según corresponda.

---

### TAREA 2: Prevenir Sesiones Duplicadas

**Archivo: `functions/src/functions/table.ts` - función `joinTable`**

**Verificar y mejorar:**
1. La verificación de sesión existente ANTES de la transacción (líneas 262-287) está bien
2. DENTRO de la transacción (líneas 290-360), debe haber OTRA verificación para evitar race conditions
3. Si se encuentra una sesión activa dentro de la transacción, debe retornar esa sesión, NO crear una nueva

**Código a revisar:**
```typescript
// Dentro de la transacción (después de línea 290)
// Debe haber una verificación adicional:
const duplicateCheck = await db.collection('poker_sessions')
    .where('userId', '==', uid)
    .where('roomId', '==', roomId)
    .where('status', '==', 'active')
    .limit(1)
    .get();

if (!duplicateCheck.empty) {
    const existingSessionId = duplicateCheck.docs[0].id;
    console.log(`[JOIN_TABLE] ⚠️ DUPLICADO DETECTADO EN TRANSACCIÓN: Sesión ${existingSessionId} ya existe`);
    return { type: 'existing', sessionId: existingSessionId };
}
```

**Nota:** Las queries NO se pueden hacer dentro de transacciones de Firestore. En su lugar, debe:
1. Leer el documento del usuario dentro de la transacción
2. Verificar si `currentTableId` ya está establecido para esta mesa
3. Si está establecido, buscar la sesión activa (pero esto requiere leer fuera de la transacción)

**Solución alternativa:**
- Mantener la verificación ANTES de la transacción (ya existe)
- Dentro de la transacción, verificar el campo `currentTableId` del usuario
- Si `currentTableId === roomId`, significa que ya hay una sesión activa, abortar

---

### TAREA 3: Verificar Cálculo del Rake y Distribución

**Archivo: `functions/src/functions/table.ts` - función `processCashOut`**

**Verificar:**
1. **Cálculo del Rake (líneas 564-567):**
   ```typescript
   const grossProfit = realChips - buyInOriginal;
   const rakeAmount = grossProfit > 0 ? Math.floor(grossProfit * RAKE_PERCENTAGE) : 0;
   const payout = realChips - rakeAmount;
   ```
   ✅ Esto está CORRECTO según el README

2. **Distribución del Rake (líneas 625-725):**
   - Mesa Privada: 100% a plataforma ✅
   - Mesa Pública: 50% Plataforma / 30% Club / 20% Seller ✅
   - Verificar que los cálculos de redondeo sean correctos

3. **Limpieza de Estado (líneas 615-620):**
   ```typescript
   transaction.update(userRef, {
       credit: admin.firestore.FieldValue.increment(payout),
       moneyInPlay: 0,
       currentTableId: null,
       lastUpdated: timestamp
   });
   ```
   ✅ Esto está CORRECTO según el README

**Archivo: `server/src/middleware/firebaseAuth.ts` - función `endPokerSession`**

**Problema:** Esta función también puede estar interfiriendo con el ciclo económico.

**Verificar:**
1. Esta función NO debe crear registros en `financial_ledger` con tipo `GAME_LOSS`
2. Debe usar `SESSION_CLOSE` o `SESSION_END`
3. El cálculo del rake debe ser consistente con `processCashOut`

**Recomendación:** Si `processCashOut` ya maneja todo correctamente, verificar que `endPokerSession` no esté duplicando lógica o creando conflictos.

---

### TAREA 4: Verificar `settleGameRound`

**Archivo: `functions/src/functions/gameEconomy.ts`**

**Según el README, `settleGameRound` NO debe:**
- ❌ Transferir crédito a la billetera del usuario
- ❌ Limpiar `moneyInPlay` o `currentTableId`
- ❌ Resetear las fichas del ganador a 0 en la mesa
- ❌ Cerrar la sesión o cambiar su estado

**DEBE:**
- ✅ Calcular el rake del bote (8% del pot total)
- ✅ Distribuir el rake según tipo de mesa
- ✅ Actualizar las fichas del ganador en `poker_tables/{tableId}.players[].chips`
- ✅ Actualizar `poker_sessions/{sessionId}.totalRakePaid` (acumular rake pagado)
- ✅ Registrar en `financial_ledger` (auditoría de la mano)
- ✅ Actualizar estadísticas diarias

**Verificar:** Revisar el código completo de `settleGameRound` y asegurar que NO esté haciendo cashout prematuro.

---

## 🔍 VERIFICACIONES FINALES

Después de hacer los cambios, verificar:

1. **No hay sesiones duplicadas:**
   - Un usuario solo puede tener 1 sesión activa por mesa
   - Si intenta unirse dos veces, debe retornar la sesión existente

2. **Tipos de transacción correctos:**
   - Buscar en todo el código: `grep -r "GAME_LOSS" .`
   - Solo debe aparecer en comentarios o en código legacy que no se usa
   - Todos los cierres de sesión deben usar `SESSION_CLOSE` o `SESSION_END`

3. **Economía funciona:**
   - El rake se calcula sobre la ganancia bruta (GrossProfit = FichasFinales - BuyIn)
   - El rake se distribuye correctamente según tipo de mesa
   - Los balances se actualizan correctamente
   - `moneyInPlay` y `currentTableId` se limpian al hacer cashout

4. **Flujo completo:**
   - Entrada: `joinTable` → Descuenta de `credit`, establece `moneyInPlay`, crea sesión
   - Juego: `settleGameRound` → Actualiza fichas en mesa, distribuye rake, NO transfiere a billetera
   - Salida: `processCashOut` → Lee fichas de mesa, calcula rake, transfiere a billetera, limpia estado

---

## 📝 NOTAS IMPORTANTES

1. **Fuente de Verdad:** Las fichas del usuario son las que tiene en `poker_tables/{tableId}.players[].chips`, NO en `poker_sessions.currentChips`

2. **Idempotencia:** `joinTable` debe ser idempotente - si el usuario ya tiene sesión activa, retornar esa sesión

3. **Limpieza Obligatoria:** Al hacer cashout, SIEMPRE limpiar `moneyInPlay: 0` y `currentTableId: null`

4. **Rake:** Se calcula sobre la ganancia bruta (GrossProfit), NO sobre el stack total

5. **Transacciones Atómicas:** Todas las operaciones financieras deben estar en transacciones atómicas de Firestore

---

## 🚀 ORDEN DE EJECUCIÓN

1. Primero: Cambiar `GAME_LOSS` por `SESSION_CLOSE` o `SESSION_END`
2. Segundo: Mejorar prevención de sesiones duplicadas en `joinTable`
3. Tercero: Verificar y corregir cálculos de rake y distribución
4. Cuarto: Verificar que `settleGameRound` no haga cashout prematuro
5. Quinto: Probar el flujo completo y verificar que todo funcione según el README

---

**Última actualización:** 2025-12-15
**Prioridad:** ALTA - El sistema económico no funciona correctamente

