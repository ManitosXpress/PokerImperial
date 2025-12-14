# 🔒 Liquidación Universal - Función a Prueba de Balas

## 🎯 Objetivo

La función `universalTableSettlement` garantiza que **TODOS** los jugadores sean procesados correctamente al cerrar una mesa, sin importar el motivo. Es la solución definitiva para evitar indicadores visuales stuck.

---

## 📋 Función Principal: `universalTableSettlement`

### Características Críticas

✅ **Iteración Obligatoria**: Recorre la lista de players uno por uno, sin asumir nada  
✅ **Limpieza Visual Garantizada**: Establece `moneyInPlay: 0` y `currentTableId: null` para **TODOS** los jugadores  
✅ **Cálculo Financiero Correcto**: Calcula rake y payout de forma precisa  
✅ **Registro Completo**: Registra en `financial_ledger` con todos los detalles  
✅ **Cierre Seguro**: Solo cierra la mesa después de procesar **TODOS** los jugadores  

### Lógica de Liquidación (Paso a Paso)

#### Para CADA Jugador (Ganador o Perdedor):

**Paso A - Limpieza Visual (CRÍTICO):**
```typescript
transaction.update(userRef, {
    moneyInPlay: 0,        // Establecer explícitamente a 0 (NO delete)
    currentTableId: null,  // Establecer explícitamente a null (NO delete)
    lastUpdated: timestamp
});
```
⚠️ **Esto DEBE pasar para TODOS los jugadores, sin excepción.**

**Paso B - Cálculo Financiero:**
- `FinalStack` = Fichas que tiene en ese momento
- `InitialBuyIn` = Buy-in original de la sesión
- `NetResult` = `FinalStack - InitialBuyIn`

**Paso C - Rake y Transferencia:**

**Si NetResult > 0 (Ganador):**
- Calcula `Rake = FinalStack * 8%`
- `Payout = FinalStack - Rake`
- `userRef.update({ credit: FieldValue.increment(Payout) })`
- Registra en Ledger: `TYPE: GAME_WIN, Amount: Payout`

**Si NetResult <= 0 (Perdedor o Empate):**
- Si le quedaron fichas: `credit: FieldValue.increment(FinalStack)`
- Registra en Ledger: `TYPE: GAME_LOSS, Amount: -LossAmount`

**Cierre de Mesa:**
- Solo después de procesar **TODOS** los jugadores
- Marca mesa como `status: 'FINISHED'`
- Todos los jugadores quedan con `chips: 0, inGame: false`

---

## 🚀 Uso de la Función

### Desde Cloud Function (Callable):

```typescript
const functions = FirebaseFunctions.instance;
const result = await functions.httpsCallable('universalTableSettlementFunction').call({
    tableId: 'MESA_ID'
});
```

### Desde el Backend (Node.js):

```typescript
import { universalTableSettlement } from './functions/table';

await universalTableSettlement({ tableId: 'MESA_ID' }, context);
```

### Respuesta de Ejemplo:

```json
{
  "success": true,
  "playersProcessed": 4,
  "totalRakeCollected": 320,
  "players": [
    {
      "userId": "user123",
      "displayName": "Jugador 1",
      "finalStack": 5000,
      "initialBuyIn": 1000,
      "netResult": 4000,
      "payout": 4600,
      "rake": 400,
      "type": "GAME_WIN"
    },
    {
      "userId": "user456",
      "displayName": "Jugador 2",
      "finalStack": 0,
      "initialBuyIn": 1000,
      "netResult": -1000,
      "payout": 0,
      "rake": 0,
      "type": "GAME_LOSS"
    }
  ],
  "message": "Universal settlement completed. 4 players processed."
}
```

---

## 🛠️ Script de Corrección: `cleanStuckMoneyInPlay`

### Objetivo

Limpia usuarios con `moneyInPlay > 0` que NO están jugando activamente. Este script debe ejecutarse **una sola vez** para limpiar la base de datos actual.

### Uso desde PowerShell:

```powershell
# Modo Dry Run (recomendado primero)
Invoke-RestMethod -Uri "https://us-central1-poker-fa33a.cloudfunctions.net/cleanStuckMoneyInPlay" -Method Post -ContentType "application/json" -Body '{"dryRun": true}'

# Ejecución Real
Invoke-RestMethod -Uri "https://us-central1-poker-fa33a.cloudfunctions.net/cleanStuckMoneyInPlay" -Method Post -ContentType "application/json" -Body '{}'
```

### Lógica del Script:

1. Busca usuarios con `moneyInPlay > 0`
2. Verifica si están en una mesa activa:
   - Si la mesa está `'active'` y el jugador está en ella → **SALTAR** (no es un bug)
   - Si la mesa no existe o está inactiva → **LIMPIAR**
3. Verifica si tienen sesión activa:
   - Si tienen sesión `'active'` sin `endTime` → **SALTAR** (sesión válida)
   - Si tienen sesión con `endTime` → **LIMPIAR** (inconsistencia)
4. Resetea `moneyInPlay: 0` y `currentTableId: null`

### Respuesta de Ejemplo:

```json
{
  "success": true,
  "message": "Stuck moneyInPlay users cleaned successfully.",
  "cleaned": 3,
  "skipped": 1,
  "dryRun": false,
  "cleanedUsers": [
    {
      "uid": "user123",
      "email": "test@example.com",
      "displayName": "Test User",
      "moneyInPlay": 1000,
      "currentTableId": "table456"
    }
  ],
  "skippedUsers": [
    {
      "uid": "user789",
      "reason": "Está en una mesa activa"
    }
  ]
}
```

---

## 🔧 Integración con el Sistema Actual

### Reemplazar `closeTableAndCashOut`:

La función `universalTableSettlement` puede reemplazar o complementar `closeTableAndCashOut`. Para usarla:

1. **Opción A**: Reemplazar completamente `closeTableAndCashOut` por `universalTableSettlement`
2. **Opción B**: Usar `universalTableSettlement` como fallback cuando `closeTableAndCashOut` falle
3. **Opción C**: Usar ambas, pero siempre ejecutar `universalTableSettlement` después de `closeTableAndCashOut` como verificación

### Recomendación:

Usar `universalTableSettlement` como función principal y mantener `closeTableAndCashOut` para compatibilidad hacia atrás.

---

## 📊 Comparación: Antes vs Después

### ❌ ANTES (Problema):

```typescript
// Solo limpiaba si netWinnings > 0
if (netWinnings > 0) {
    transaction.update(userRef, {
        credit: FieldValue.increment(netWinnings),
        currentTableId: FieldValue.delete(),  // ❌ Delete puede fallar
        moneyInPlay: FieldValue.delete()      // ❌ Delete puede fallar
    });
} else {
    // ❌ A veces no limpiaba para perdedores
}
```

### ✅ AHORA (Solución):

```typescript
// Limpieza OBLIGATORIA para TODOS (ganadores y perdedores)
transaction.update(userRef, {
    moneyInPlay: 0,        // ✅ Establecer explícitamente
    currentTableId: null,  // ✅ Establecer explícitamente
    lastUpdated: timestamp
});

// Luego actualizar crédito según corresponda
if (netResult > 0) {
    transaction.update(userRef, {
        credit: FieldValue.increment(payout)
    });
}
```

---

## ⚠️ Notas Importantes

1. **Transacción Atómica**: Todo el proceso se ejecuta en una sola transacción de Firestore para garantizar consistencia.

2. **No Asume Nada**: La función lee todos los datos necesarios antes de la transacción y verifica cada condición.

3. **Limpieza Garantizada**: `moneyInPlay: 0` y `currentTableId: null` se establecen **SIEMPRE**, sin importar el resultado del juego.

4. **Rake Correcto**: El rake se calcula sobre `FinalStack`, no sobre la ganancia neta.

5. **Registro Completo**: Todos los movimientos se registran en `financial_ledger` con todos los detalles necesarios.

---

## 🚨 Troubleshooting

### El indicador sigue apareciendo después de ejecutar:

1. Ejecuta el script de corrección: `cleanStuckMoneyInPlay`
2. Verifica que la función se ejecutó correctamente (revisa logs)
3. Refresca la aplicación Flutter
4. Verifica que el stream de `inGameBalance` se actualice

### Error: "Table not found"

- Verifica que el `tableId` sea correcto
- Verifica que la mesa exista en Firestore

### Error: "User not found"

- La función continúa con el siguiente jugador
- Revisa los logs para ver qué jugadores fueron saltados

---

## 📝 Checklist de Implementación

- [x] Función `universalTableSettlement` creada
- [x] Script `cleanStuckMoneyInPlay` creado
- [x] Exportada en `functions/src/index.ts`
- [x] Limpieza visual obligatoria implementada
- [x] Cálculo de rake correcto
- [x] Registro en ledger completo
- [x] Cierre de mesa seguro

---

## 🎯 Próximos Pasos

1. **Desplegar Cloud Functions:**
   ```bash
   cd functions
   npm run deploy
   ```

2. **Ejecutar Script de Corrección (Dry Run primero):**
   ```powershell
   .\reparar-sesiones.ps1  # Para sesiones stuck
   # Y luego:
   Invoke-RestMethod -Uri "https://us-central1-poker-fa33a.cloudfunctions.net/cleanStuckMoneyInPlay" -Method Post -ContentType "application/json" -Body '{"dryRun": true}'
   ```

3. **Reemplazar llamadas a `closeTableAndCashOut` por `universalTableSettlement`** (opcional pero recomendado)

4. **Probar cierre de mesa** y verificar que el indicador "+X en mesa" desaparezca correctamente

---

## ✅ Estado Final

- ✅ **Función universal creada**: Procesa todos los jugadores de forma segura
- ✅ **Limpieza visual garantizada**: `moneyInPlay: 0` y `currentTableId: null` para todos
- ✅ **Script de corrección listo**: Limpia usuarios stuck existentes
- ✅ **Sin errores de linting**: Todo el código está limpio

**El sistema ahora tiene una función a prueba de balas para liquidar mesas correctamente.**

