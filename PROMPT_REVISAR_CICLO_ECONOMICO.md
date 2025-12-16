"Actúa como un Senior Fintech Architect & Database Engineer experto en Google Cloud Firestore.

## 📋 CONTEXTO

El sistema de poker tiene una arquitectura con **separación clara** entre:
- **`server/`**: Usado para **WebSocket** (Socket.io) y **render** - Comunicación en tiempo real
- **`functions/`**: Usado para **lógica de negocio** (Cloud Functions) - Transacciones financieras

**PROBLEMA CRÍTICO**: Actualmente hay **DOS lugares** donde se pueden crear sesiones de poker, lo que puede causar **duplicación de sesiones** y confusión en el ciclo económico.

---

## 🎯 OBJETIVO

Revisar y corregir el código para que:
1. ✅ **NO se dupliquen las sesiones** - Un usuario NUNCA puede tener más de 1 sesión activa por mesa
2. ✅ **Separación clara** entre `server/` (websocket) y `functions/` (lógica)
3. ✅ **Funcione correctamente** según `README_CICLO_ECONOMICO.md`
4. ✅ **Fuente única de verdad** para creación de sesiones

---

## 🏗️ ARQUITECTURA: Separación Server/Functions

### **`server/` - WebSocket y Render (NO lógica financiera)**

**Propósito:**
- Manejar conexiones WebSocket (Socket.io)
- Renderizar el juego en tiempo real
- Comunicación bidireccional cliente-servidor
- **NO debe crear sesiones directamente**
- **NO debe modificar créditos directamente**

**Archivos clave:**
- `server/src/index.ts` - Eventos WebSocket (`join_room`, `create_room`)
- `server/src/middleware/firebaseAuth.ts` - Autenticación y helpers
- `server/src/game/RoomManager.ts` - Gestión de salas en memoria

**Regla de Oro:**
- `server/` puede **llamar** a Cloud Functions (`joinTable`, `processCashOut`)
- `server/` **NO debe** crear sesiones directamente en Firestore
- `server/` **NO debe** modificar `users/{uid}.credit` directamente

---

### **`functions/` - Lógica de Negocio (Cloud Functions)**

**Propósito:**
- **ÚNICA fuente de verdad** para operaciones financieras
- Crear y gestionar sesiones de poker
- Calcular y distribuir rake
- Modificar créditos de usuarios
- Transacciones atómicas de Firestore

**Archivos clave:**
- `functions/src/functions/table.ts` - `joinTable()`, `processCashOut()`
- `functions/src/functions/gameEconomy.ts` - `settleGameRound()`

**Regla de Oro:**
- `functions/` es la **ÚNICA** fuente de verdad para sesiones
- Todas las operaciones financieras deben pasar por Cloud Functions
- Todas las transacciones deben ser atómicas

---

## ⚠️ PROBLEMA IDENTIFICADO: Duplicación de Sesiones

### **Dos lugares crean sesiones:**

1. **`server/src/middleware/firebaseAuth.ts`** - `reservePokerSession()`
   - Se llama desde eventos WebSocket (`join_room`, `create_room`)
   - Crea sesiones directamente en Firestore
   - Modifica `users/{uid}.credit` directamente

2. **`functions/src/functions/table.ts`** - `joinTable()`
   - Cloud Function callable
   - Crea sesiones en transacciones atómicas
   - Modifica `users/{uid}.credit` en transacciones

**Riesgo:**
- Si ambos se llaman para el mismo usuario/mesa → **Sesiones duplicadas**
- Race conditions entre WebSocket y Cloud Function
- Inconsistencias en el estado financiero

---

## ✅ SOLUCIÓN PROPUESTA

### **Opción 1: Server llama a Cloud Function (RECOMENDADO)**

**Cambio:**
- `server/` **NO debe** llamar a `reservePokerSession()` directamente
- `server/` **DEBE** llamar a la Cloud Function `joinTable()` vía HTTP callable

**Implementación:**
```typescript
// server/src/index.ts - Evento 'join_room'
socket.on('join_room', async ({ roomId, playerName, token }) => {
    // ... validaciones ...
    
    // ❌ ANTES (INCORRECTO):
    // sessionId = await reservePokerSession(uid, entryFee, roomId);
    
    // ✅ DESPUÉS (CORRECTO):
    const joinTableFunction = functions.httpsCallable('joinTable');
    const result = await joinTableFunction({ 
        roomId: roomId, 
        buyInAmount: entryFee 
    });
    sessionId = result.data.sessionId;
    
    // ... resto del código ...
});
```

**Ventajas:**
- ✅ Una sola fuente de verdad (`functions/joinTable`)
- ✅ Transacciones atómicas garantizadas
- ✅ Idempotencia centralizada
- ✅ Consistencia total

---

### **Opción 2: Server solo valida, Functions crea (ALTERNATIVA)**

Si por alguna razón necesitas mantener `reservePokerSession()` en server:

**Cambio:**
- `server/reservePokerSession()` solo debe **validar** (balance, mesa existe)
- `server/reservePokerSession()` **NO debe** crear sesión
- `server/reservePokerSession()` debe **llamar** a `functions/joinTable()` para crear

**Implementación:**
```typescript
// server/src/middleware/firebaseAuth.ts
export async function reservePokerSession(uid: string, amount: number, roomId: string): Promise<string | null> {
    // 1. Validaciones rápidas (sin crear sesión)
    const balance = await getUserBalance(uid);
    if (balance < amount) {
        return null;
    }
    
    // 2. Llamar a Cloud Function (fuente de verdad)
    const joinTableFunction = functions.httpsCallable('joinTable');
    try {
        const result = await joinTableFunction({ 
            roomId: roomId, 
            buyInAmount: amount 
        });
        return result.data.sessionId;
    } catch (error) {
        console.error('Error calling joinTable:', error);
        return null;
    }
}
```

---

## 🔍 TAREAS DE REVISIÓN

### **TAREA 1: Identificar todos los lugares donde se crean sesiones**

**Buscar en código:**
```bash
# Buscar creación de sesiones
grep -r "poker_sessions.*doc()" server/ functions/
grep -r "collection('poker_sessions')" server/ functions/
grep -r "reservePokerSession" server/ functions/
grep -r "joinTable" server/ functions/
```

**Archivos a revisar:**
1. `server/src/index.ts` - Eventos `join_room`, `create_room`
2. `server/src/middleware/firebaseAuth.ts` - Función `reservePokerSession()`
3. `functions/src/functions/table.ts` - Función `joinTable()`

**Verificar:**
- ¿Cuántos lugares crean sesiones?
- ¿Hay conflictos entre ellos?
- ¿Cuál es la fuente de verdad actual?

---

### **TAREA 2: Eliminar duplicación - Elegir una fuente única**

**Decisión requerida:**
- ¿`server/reservePokerSession()` debe eliminarse?
- ¿O debe convertirse en un wrapper que llama a `functions/joinTable()`?

**Acción:**
- Si se elimina `reservePokerSession()`: Actualizar todos los lugares que la llaman
- Si se convierte en wrapper: Implementar llamada a Cloud Function

---

### **TAREA 3: Verificar idempotencia en `functions/joinTable()`**

**Archivo:** `functions/src/functions/table.ts` - Función `joinTable()`

**Verificar:**
1. ✅ Pre-check de sesión existente ANTES de transacción (líneas 288-312)
2. ✅ Verificación DENTRO de transacción (líneas 337-349)
3. ✅ Si existe sesión, retornar esa (NO crear nueva)

**Código a revisar:**
```typescript
// Dentro de la transacción (línea 337)
const sessionCheckQuery = await db.collection('poker_sessions')
    .where('userId', '==', uid)
    .where('roomId', '==', roomId)
    .where('status', '==', 'active')
    .limit(1)
    .get();

if (!sessionCheckQuery.empty) {
    // ✅ CORRECTO: Retornar sesión existente
    return { type: 'existing', sessionId: existingId };
}
```

**Problema potencial:**
- Las queries NO se pueden hacer dentro de transacciones de Firestore
- **Solución:** Verificar `currentTableId` del usuario dentro de la transacción

**Código corregido:**
```typescript
// Dentro de la transacción
const userData = userDoc.data();
const currentTableId = userData?.currentTableId || null;

// Si ya está en esta mesa, buscar sesión existente (fuera de transacción)
if (currentTableId === roomId) {
    // Buscar sesión activa (esto debe hacerse ANTES de la transacción)
    // O mejor: retornar error indicando que ya está en la mesa
    throw new functions.https.HttpsError(
        'already-exists',
        `User already in table ${roomId}. Use existing session.`
    );
}
```

---

### **TAREA 4: Verificar que `processCashOut()` maneje sesiones duplicadas**

**Archivo:** `functions/src/functions/table.ts` - Función `processCashOut()`

**Verificar:**
1. ✅ Busca TODAS las sesiones activas (líneas 553-557)
2. ✅ Identifica sesión primaria (más reciente) y duplicados (líneas 570-579)
3. ✅ Cierra TODAS las sesiones en una sola transacción (líneas 631-767)

**Código a revisar:**
```typescript
// Línea 553-557: Buscar todas las sesiones activas
const activeSessionsQuery = await db.collection('poker_sessions')
    .where('userId', '==', targetUserId)
    .where('roomId', '==', tableId)
    .where('status', '==', 'active')
    .get();

// Línea 570-579: Identificar primaria y duplicados
const allSessions = activeSessionsQuery.docs
    .map(doc => ({ id: doc.id, ref: doc.ref, data: doc.data() }))
    .sort((a, b) => {
        const aTime = a.data.startTime?.toMillis() || 0;
        const bTime = b.data.startTime?.toMillis() || 0;
        return bTime - aTime; // Más reciente primero
    });

const primarySession = allSessions[0];
const duplicateSessions = allSessions.slice(1);
```

**Verificar:**
- ✅ Si hay duplicados, se marcan como `ERROR_DUPLICATE`
- ✅ Solo la sesión primaria se usa para cálculos
- ✅ Todas se cierran en la misma transacción

---

### **TAREA 5: Verificar separación Server/Functions en cierre de sesión**

**Problema potencial:**
- `server/endPokerSession()` también puede cerrar sesiones
- `functions/processCashOut()` también cierra sesiones
- ¿Cuál es la fuente de verdad?

**Archivos a revisar:**
1. `server/src/middleware/firebaseAuth.ts` - `endPokerSession()`
2. `functions/src/functions/table.ts` - `processCashOut()`

**Decisión requerida:**
- ¿`server/endPokerSession()` debe eliminarse?
- ¿O debe convertirse en wrapper que llama a `functions/processCashOut()`?

**Recomendación:**
- `server/endPokerSession()` debe llamar a `functions/processCashOut()`
- O eliminarse completamente si no se usa

---

## 📝 CHECKLIST DE VERIFICACIÓN

### **Separación Server/Functions:**
- [ ] `server/` NO crea sesiones directamente
- [ ] `server/` llama a Cloud Functions para operaciones financieras
- [ ] `functions/` es la única fuente de verdad para sesiones
- [ ] No hay código duplicado entre server y functions

### **Prevención de Duplicados:**
- [ ] Solo UN lugar crea sesiones (`functions/joinTable`)
- [ ] `joinTable()` tiene idempotencia robusta (pre-check + transacción)
- [ ] `processCashOut()` maneja sesiones duplicadas correctamente
- [ ] Logs claros para detectar duplicados

### **Ciclo Económico:**
- [ ] `joinTable()` descuenta de `credit`, establece `moneyInPlay`, crea sesión
- [ ] `settleGameRound()` actualiza fichas en mesa, distribuye rake, NO transfiere a billetera
- [ ] `processCashOut()` lee fichas de mesa, calcula rake, transfiere a billetera, limpia estado
- [ ] `moneyInPlay: 0` y `currentTableId: null` siempre se limpian al salir

### **Fuente de Verdad:**
- [ ] Fichas del usuario: `poker_tables/{tableId}.players[].chips` (NO `poker_sessions.currentChips`)
- [ ] Sesiones: Solo se crean en `functions/joinTable()`
- [ ] Cashout: Solo se procesa en `functions/processCashOut()`

---

## 🚀 ORDEN DE EJECUCIÓN

1. **Paso 1:** Identificar todos los lugares donde se crean sesiones
2. **Paso 2:** Elegir fuente única (recomendado: `functions/joinTable`)
3. **Paso 3:** Refactorizar `server/` para llamar a Cloud Functions
4. **Paso 4:** Verificar idempotencia en `joinTable()`
5. **Paso 5:** Verificar manejo de duplicados en `processCashOut()`
6. **Paso 6:** Probar flujo completo y verificar que no haya duplicados

---

## 📚 REFERENCIAS

- `README_CICLO_ECONOMICO.md` - Documentación del ciclo económico
- `functions/src/functions/table.ts` - Cloud Functions de mesas
- `server/src/index.ts` - Eventos WebSocket
- `server/src/middleware/firebaseAuth.ts` - Helpers de autenticación

---

**Última actualización:** 2025-01-XX
**Prioridad:** CRÍTICA - Duplicación de sesiones puede causar pérdidas financieras

