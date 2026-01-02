# Análisis de Fallas Backend Poker Imperial

Este documento detalla los errores encontrados en el backend del proyecto Poker Imperial y las soluciones aplicadas.

## 1. Rake no distribuido (Winner IDs vacíos)

**Síntoma:**
En los logs aparecía: `💰 [DEBUG] Extracted winnerIds: []` y `💰 [DEBUG] Player ... -> UID: NOT FOUND`.

**Causa:**
Cuando se creaba una sala (`createRoom` en `RoomManager.ts`), el objeto `Player` del host se inicializaba sin la propiedad `uid`. Al ganar una mano, el sistema intentaba extraer el UID del ganador, pero al no existir, el array `winnerIds` quedaba vacío.

**Solución:**
Se modificó `RoomManager.ts` para asignar explícitamente `uid: hostUid` al crear el objeto jugador del host.

```typescript
// RoomManager.ts
const host: Player = {
    id: hostId,
    uid: hostUid, // ✅ FIX: Asignar UID explícitamente
    // ...
};
```

## 2. Error de Escritura en Firestore (Undefined Value)

**Síntoma:**
Error: `Value for argument "data" is not a valid Firestore document. Cannot use "undefined" as a Firestore value (found in field "winnerUid")`.

**Causa:**
En `triggerRoundSettlement`, si el objeto `winner` no tenía `uid` (por el error anterior o por ser un bot), el campo `winnerUid` se enviaba como `undefined` a Firestore, lo cual no está permitido.

**Solución:**
1.  Se añadió validación en `RoomManager.ts` para asegurar que `winnerUid` nunca sea `undefined` (usando `null` como fallback).
2.  Se actualizó `PokerGame.ts` para asegurar que el payload de autenticación también use `null` si no hay UID.

```typescript
// RoomManager.ts
const winnerUid = data.winner?.uid || null; // ✅ FIX: Fallback a null
```

## 3. Error 401 Unauthenticated en Cashout

**Síntoma:**
Logs mostrando: `⚠️ HTTP Error 401: {"error":{"message":"Unauthenticated","status":"UNAUTHENTICATED"}}` al intentar llamar a `processCashOutFunction`.

**Causa:**
El servidor intentaba llamar a las Cloud Functions (`processCashOutFunction`) vía HTTP sin proporcionar un token de autenticación válido. Las Cloud Functions "Callable" requieren un token de usuario o de administrador.

**Solución:**
El archivo `firebaseAuth.ts` en el entorno local ya contiene la lógica "Legacy/Fallback" que realiza las escrituras directamente en Firestore usando el SDK de Admin, evitando la llamada HTTP.
**Acción Requerida:** Asegurarse de desplegar la versión local de `server/src/middleware/firebaseAuth.ts` al servidor de producción.

## Resumen de Cambios

-   **`server/src/game/RoomManager.ts`**:
    -   Corregido `createRoom` para incluir `uid`.
    -   Corregido `triggerRoundSettlement` para validar `winnerUid`.
-   **`server/src/game/PokerGame.ts`**:
    -   Corregido `evaluateWinner` para usar `null` en lugar de `undefined` en `authPayload`.

Con estos cambios, el flujo de rake y cashout debería funcionar correctamente, registrando las transacciones en Firestore sin errores.
