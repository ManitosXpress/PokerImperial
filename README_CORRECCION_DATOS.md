# 🔧 Corrección de Corrupción de Datos - Sistema de Poker

## 📋 Índice

- [Problema Identificado](#problema-identificado)
- [Solución Implementada](#solución-implementada)
- [Funciones Creadas](#funciones-creadas)
- [Script de Limpieza](#script-de-limpieza)
- [Uso y Ejemplos](#uso-y-ejemplos)
- [Arquitectura](#arquitectura)
- [Validaciones de Seguridad](#validaciones-de-seguridad)

---

## 🚨 Problema Identificado

### Estado de Emergencia

El sistema presentaba corrupción de datos crítica:

1. **Bug 'new_room'**: Se estaban creando documentos en `poker_sessions` con `roomId: "new_room"`, indicando que el backend aceptaba peticiones de unión antes de que la sala tuviera un ID real.

2. **Triplicidad de Sesiones**: Un solo usuario tenía 3 sesiones activas para la misma partida, causando:
   - Cobro múltiple del Buy-In
   - Pérdidas financieras incorrectas (ej: -3000 en vez de -1000)
   - Falta de cálculo del Rake

3. **Desastre Financiero**: Al cerrar la mesa, el sistema:
   - Cobraba múltiples veces el Buy-In
   - No calculaba correctamente el Rake
   - Generaba inconsistencias en los saldos de usuarios

---

## ✅ Solución Implementada

Se implementó una reescritura total de la lógica de **Entrada** (`joinTable`) y **Salida** (`processCashOut`) con validaciones estrictas y un script de saneamiento para limpiar datos corruptos existentes.

---

## 🔨 Funciones Creadas

### 1. `joinTable` - Blindaje de Entrada

**Ubicación**: `functions/src/functions/table.ts`

**Tipo**: Cloud Function (Callable)

**Propósito**: Función blindada para unirse a una mesa con validaciones estrictas anti-duplicados y anti-'new_room'.

#### Validaciones Implementadas

1. **Validación de ID**: Rechaza cualquier petición con `roomId === 'new_room'` o vacío
   ```typescript
   if (!roomId || roomId === 'new_room' || roomId.trim() === '') {
       throw new functions.https.HttpsError('invalid-argument', 'Invalid Room ID');
   }
   ```

2. **Idempotencia (Anti-Clonación)**:
   - Query previa: `poker_sessions.where('userId', '==', uid).where('roomId', '==', roomId).where('status', '==', 'active')`
   - Si existe: Retorna el ID de la sesión existente
   - Si NO existe: Crea la sesión nueva dentro de una transacción atómica

3. **Doble Verificación**: Verificación adicional dentro de la transacción para prevenir race conditions

4. **Limpieza Automática**: Limpia estados stuck del usuario (moneyInPlay en otra mesa)

#### Parámetros

```typescript
interface JoinTableRequest {
    roomId: string;        // ID válido de la mesa (NO puede ser 'new_room')
    buyInAmount?: number;  // Opcional: monto del buy-in (usa minBuyIn de la mesa si no se proporciona)
}
```

#### Respuesta

```typescript
{
    success: true,
    sessionId: string,      // ID de la sesión (existente o nueva)
    isExisting: boolean,    // true si ya existía, false si se creó
    message: string
}
```

#### Ejemplo de Uso

```typescript
// Desde el cliente (Flutter/Web)
final result = await FirebaseFunctions.instance.httpsCallable('joinTableFunction').call({
    'roomId': 'abc123',  // ID válido de la mesa
    'buyInAmount': 1000  // Opcional
});

print('Session ID: ${result.data['sessionId']}');
```

---

### 2. `processCashOut` - Consolidación y Liquidación

**Ubicación**: `functions/src/functions/table.ts`

**Tipo**: Cloud Function (Callable)

**Propósito**: Función de consolidación que limpia sesiones duplicadas y calcula correctamente el cashout final.

#### Algoritmo de Consolidación

**Paso A: Consolidación**
- Busca TODAS las sesiones del usuario en esa sala (activas o completed)
- Toma solo la más reciente como válida
- Marca el resto como `status: 'duplicate_error'` para ignorarlas matemáticamente

**Paso B: Cálculo Único**
- Usa `player.chips` de la mesa como **Fuente de Verdad**
- `NetResult = player.chips - BuyInAmount`

**Paso C: Rake y Ledger**
- Calcula el Rake solo si `NetResult > 0`
- Guarda el Rake en `system_stats/economy`
- Escribe un único registro en `financial_ledger`:
  - Type: `SESSION_END` (neutral)
  - Amount: `NetResult` (puede ser positivo o negativo)
  - Details: "Cashout Final - Chips: X, BuyIn: Y, Rake: Z"

#### Parámetros

```typescript
interface ProcessCashOutRequest {
    tableId: string;      // ID de la mesa
    userId?: string;      // Opcional: ID del usuario (por defecto usa el autenticado)
}
```

#### Respuesta

```typescript
{
    success: true,
    sessionId: string,              // ID de la sesión primaria
    playerChips: number,            // Chips finales del jugador
    buyInAmount: number,            // Buy-in original
    netResult: number,              // Resultado neto (puede ser negativo)
    rakeAmount: number,             // Rake calculado (solo si netResult > 0)
    finalPayout: number,            // Monto final a devolver al usuario
    duplicateSessionsClosed: number  // Cantidad de sesiones duplicadas cerradas
}
```

#### Ejemplo de Uso

```typescript
// Desde el cliente
final result = await FirebaseFunctions.instance.httpsCallable('processCashOutFunction').call({
    'tableId': 'abc123'
});

print('Net Result: ${result.data['netResult']}');
print('Rake: ${result.data['rakeAmount']}');
print('Final Payout: ${result.data['finalPayout']}');
```

---

### 3. `cleanupCorruptedSessions` - Script de Saneamiento

**Ubicación**: `functions/src/functions/admin.ts`

**Tipo**: Cloud Function (HTTP)

**Propósito**: Script HTTP para ejecutar limpieza inmediata de datos corruptos en la base de datos.

#### Funcionalidades

1. **Elimina sesiones 'new_room'**:
   - Busca todas las sesiones con `roomId: 'new_room'`
   - Las elimina
   - Restaura los créditos descontados erróneamente a los usuarios afectados

2. **Limpia sesiones duplicadas**:
   - Busca usuarios con múltiples sesiones activas en la misma sala
   - Mantiene solo la más reciente
   - Marca las demás como `'duplicate_error'`
   - Restaura créditos descontados por duplicados

3. **Recalcula saldos**:
   - Suma los créditos que se descontaron erróneamente
   - Actualiza el saldo de cada usuario afectado

#### Endpoint

```
POST https://YOUR_REGION-YOUR_PROJECT.cloudfunctions.net/cleanupCorruptedSessions
```

#### Respuesta

```json
{
    "success": true,
    "message": "Script de saneamiento completado exitosamente",
    "results": {
        "newRoomSessionsDeleted": 15,
        "duplicateSessionsCleaned": 8,
        "usersBalanceFixed": 5,
        "totalCreditsRestored": 15000,
        "errors": []
    }
}
```

#### Ejemplo de Uso

**Desde cURL:**
```bash
curl -X POST \
  https://us-central1-tu-proyecto.cloudfunctions.net/cleanupCorruptedSessions \
  -H "Content-Type: application/json"
```

**Desde Postman/Insomnia:**
- Method: `POST`
- URL: `https://YOUR_REGION-YOUR_PROJECT.cloudfunctions.net/cleanupCorruptedSessions`
- Headers: `Content-Type: application/json`

**Desde Node.js:**
```javascript
const axios = require('axios');

async function runCleanup() {
    try {
        const response = await axios.post(
            'https://YOUR_REGION-YOUR_PROJECT.cloudfunctions.net/cleanupCorruptedSessions'
        );
        console.log('Resultado:', response.data);
    } catch (error) {
        console.error('Error:', error.response?.data || error.message);
    }
}

runCleanup();
```

---

## 📊 Arquitectura

### Flujo de Entrada (joinTable)

```
Cliente → joinTableFunction
    ↓
1. Validar roomId (rechazar 'new_room')
    ↓
2. Verificar sesión existente (idempotencia)
    ↓
3. Si existe → Retornar ID existente
    ↓
4. Si NO existe → Transacción atómica:
    - Verificar balance
    - Limpiar estados stuck
    - Descontar buy-in
    - Crear sesión
    - Registrar transacción
    ↓
5. Retornar sessionId
```

### Flujo de Salida (processCashOut)

```
Cliente → processCashOutFunction
    ↓
1. Buscar TODAS las sesiones del usuario en la sala
    ↓
2. Ordenar por startTime (más reciente primero)
    ↓
3. Consolidación:
    - Sesión más reciente = VÁLIDA
    - Resto = DUPLICADAS (marcar como 'duplicate_error')
    ↓
4. Cálculo:
    - NetResult = player.chips - BuyInAmount
    - Rake = NetResult > 0 ? NetResult * 0.08 : 0
    - FinalPayout = player.chips - Rake
    ↓
5. Transacción atómica:
    - Actualizar sesión primaria
    - Cerrar sesiones duplicadas
    - Devolver crédito al usuario
    - Guardar rake en system_stats
    - Escribir ledger único
    ↓
6. Retornar resultado
```

---

## 🔒 Validaciones de Seguridad

### Validaciones en `joinTable`

1. ✅ Autenticación requerida
2. ✅ Rechazo de `roomId === 'new_room'`
3. ✅ Verificación de existencia de mesa
4. ✅ Verificación de balance suficiente
5. ✅ Idempotencia (no crear duplicados)
6. ✅ Transacción atómica (race condition protection)

### Validaciones en `processCashOut`

1. ✅ Autenticación requerida
2. ✅ Solo el propio usuario puede hacer cashout (o admin)
3. ✅ Verificación de existencia de mesa y jugador
4. ✅ Consolidación de sesiones duplicadas
5. ✅ Transacción atómica para garantizar consistencia

### Validaciones en `reservePokerSession` (Servidor)

1. ✅ Rechazo de `roomId === 'new_room'` (actualizado)
2. ✅ Idempotencia existente mantenida
3. ✅ Verificación de balance

---

## 📝 Estructura de Datos

### Sesión de Poker (`poker_sessions`)

```typescript
{
    userId: string;
    roomId: string;              // NO puede ser 'new_room'
    buyInAmount: number;
    currentChips: number;
    startTime: Timestamp;
    lastActive: Timestamp;
    status: 'active' | 'completed' | 'duplicate_error';
    totalRakePaid: number;
    netResult?: number;
    endTime?: Timestamp;
    closedReason?: string;
    note?: string;
}
```

### Ledger Financiero (`financial_ledger`)

```typescript
{
    type: 'SESSION_END' | 'GAME_WIN' | 'GAME_LOSS' | 'RAKE_COLLECTED';
    userId: string;
    userName: string;
    tableId: string;
    amount: number;              // NetResult (puede ser negativo)
    netAmount: number;           // Lo que realmente recibió
    netProfit: number;           // Ganancia/pérdida neta
    grossAmount: number;         // Chips finales
    rakePaid: number;
    buyInAmount: number;
    timestamp: Timestamp;
    description: string;
    duplicateSessionsClosed?: number;
}
```

---

## 🚀 Despliegue

### 1. Desplegar Funciones

```bash
# Desde la raíz del proyecto
cd functions
npm install  # Si hay nuevas dependencias
cd ..
firebase deploy --only functions
```

### 2. Ejecutar Script de Limpieza

**IMPORTANTE**: Ejecutar el script de limpieza **INMEDIATAMENTE** después del despliegue para limpiar datos corruptos existentes.

```bash
curl -X POST \
  https://YOUR_REGION-YOUR_PROJECT.cloudfunctions.net/cleanupCorruptedSessions \
  -H "Content-Type: application/json"
```

### 3. Verificar Logs

Revisar los logs de Cloud Functions para confirmar:
- ✅ Sesiones 'new_room' eliminadas
- ✅ Sesiones duplicadas limpiadas
- ✅ Saldos de usuarios corregidos

```bash
firebase functions:log
```

---

## 🧪 Testing

### Test Manual de `joinTable`

```typescript
// Test 1: Validación anti-'new_room'
try {
    await joinTable({ roomId: 'new_room' });
    // Debe fallar con error 'invalid-argument'
} catch (e) {
    console.log('✅ Validación funciona');
}

// Test 2: Idempotencia
const result1 = await joinTable({ roomId: 'valid-room-id' });
const result2 = await joinTable({ roomId: 'valid-room-id' });
// result1.sessionId === result2.sessionId
// result2.isExisting === true
```

### Test Manual de `processCashOut`

```typescript
// Test: Consolidación de duplicados
// 1. Crear 3 sesiones duplicadas manualmente en Firestore
// 2. Llamar processCashOut
// 3. Verificar que solo 1 sesión queda activa, las otras marcadas como 'duplicate_error'
```

---

## 📈 Monitoreo

### Métricas a Monitorear

1. **Sesiones 'new_room'**: Debe ser 0 después de la limpieza
2. **Sesiones duplicadas**: Debe ser 0 después de la limpieza
3. **Errores de validación**: Monitorear logs de `joinTable` para rechazos de 'new_room'
4. **Consolidaciones**: Monitorear `processCashOut` para ver cuántas sesiones duplicadas se están limpiando

### Queries Útiles

```javascript
// Contar sesiones 'new_room' (debe ser 0)
db.collection('poker_sessions')
  .where('roomId', '==', 'new_room')
  .get()
  .then(snap => console.log('Sesiones new_room:', snap.size));

// Contar sesiones duplicadas por usuario
db.collection('poker_sessions')
  .where('status', '==', 'active')
  .get()
  .then(snap => {
    const byUser = {};
    snap.docs.forEach(doc => {
      const data = doc.data();
      const key = `${data.userId}_${data.roomId}`;
      byUser[key] = (byUser[key] || 0) + 1;
    });
    const duplicates = Object.entries(byUser).filter(([_, count]) => count > 1);
    console.log('Duplicados encontrados:', duplicates.length);
  });
```

---

## ⚠️ Notas Importantes

1. **Ejecutar el script de limpieza INMEDIATAMENTE** después del despliegue
2. **No usar 'new_room'** como roomId en ningún lugar del código
3. **Siempre usar `joinTable`** en lugar de crear sesiones directamente
4. **Siempre usar `processCashOut`** para cerrar sesiones (consolida duplicados automáticamente)
5. **Monitorear logs** regularmente para detectar problemas temprano

---

## 🔄 Migración de Código Existente

### Antes (❌ Incorrecto)

```typescript
// ❌ NO HACER ESTO
const sessionRef = db.collection('poker_sessions').doc();
await sessionRef.set({
    userId: uid,
    roomId: 'new_room',  // ❌ INCORRECTO
    // ...
});
```

### Después (✅ Correcto)

```typescript
// ✅ USAR LA FUNCIÓN
const result = await FirebaseFunctions.instance
    .httpsCallable('joinTableFunction')
    .call({
        roomId: validTableId,  // ✅ ID válido
        buyInAmount: 1000
    });
```

---

## 📞 Soporte

Si encuentras problemas:

1. Revisa los logs de Cloud Functions
2. Verifica que el script de limpieza se ejecutó correctamente
3. Revisa que no haya código usando 'new_room' como roomId
4. Verifica que todas las llamadas usen las nuevas funciones `joinTable` y `processCashOut`

---

## 📚 Referencias

- **Archivo principal**: `functions/src/functions/table.ts`
- **Script de limpieza**: `functions/src/functions/admin.ts`
- **Servidor**: `server/src/middleware/firebaseAuth.ts`
- **Exports**: `functions/src/index.ts`

---

**Última actualización**: 2024
**Versión**: 1.0.0
**Estado**: ✅ Implementado y listo para producción

