# 🔥 README: Botón BURN (Quema de Moneda) - Integración N8N

## 📋 Descripción General

El botón **BURN** (Retirar/Quema de Moneda) es una función administrativa que permite **reducir el circulante total** del sistema de poker. Se utiliza para:

- ✅ Correcciones de balances
- ✅ Cashouts de usuarios
- ✅ Ajustes administrativos
- ✅ Reducción de liquidez total

**⚠️ IMPORTANTE:** Esta función **reduce permanentemente** el crédito del usuario y **disminuye el circulante total** del sistema.

---

## 🎯 Función Firebase

**Nombre de la función:** `adminWithdrawCreditsFunction`  
**Tipo:** Firebase Callable Function (HTTPS)  
**Endpoint:** `https://[REGION]-[PROJECT-ID].cloudfunctions.net/adminWithdrawCreditsFunction`

---

## 📥 Parámetros de Entrada

### Estructura del Request

```typescript
interface AdminWithdrawCreditsRequest {
    targetUid: string;    // ID del usuario al que se le retirarán créditos (OBLIGATORIO)
    amount: number;       // Monto a retirar (OBLIGATORIO, debe ser > 0)
    reason: string;       // Motivo de la retirada (OBLIGATORIO)
}
```

### Ejemplo de Request

```json
{
    "targetUid": "abc123xyz",
    "amount": 5000,
    "reason": "Cashout usuario - Corrección de balance"
}
```

---

## 🔄 Flujo de Ejecución

### 1. **Validaciones**
- ✅ Verifica autenticación del admin
- ✅ Valida que `targetUid` exista
- ✅ Valida que `amount` sea > 0
- ✅ Verifica que el usuario tenga suficiente balance

### 2. **Transacción Atómica (Firestore)**
La función ejecuta una transacción atómica que:

1. **Lee el balance actual del usuario**
   ```typescript
   currentBalance = userDoc.data()?.credit || 0
   ```

2. **Verifica balance suficiente**
   ```typescript
   if (currentBalance < amount) {
       throw Error("Insufficient user balance")
   }
   ```

3. **Calcula nuevo balance**
   ```typescript
   newBalance = currentBalance - amount
   ```

4. **Actualiza el usuario**
   - `users/{targetUid}.credit` = `newBalance`
   - `users/{targetUid}.lastUpdated` = timestamp

5. **Registra en `transaction_logs`**
   ```typescript
   {
       userId: targetUid,
       adminId: adminUid,
       amount: amount,
       type: "admin_debit",
       reason: reason,
       beforeBalance: currentBalance,
       afterBalance: newBalance,
       hash: transactionHash,
       metadata: { action: "burn_liquidity" }
   }
   ```

6. **Registra en `financial_ledger`**
   ```typescript
   {
       type: "ADMIN_BURN",
       userId: targetUid,
       adminId: adminUid,
       amount: amount,
       description: reason,
       timestamp: serverTimestamp()
   }
   ```

7. **Actualiza `system_stats/economy`**
   ```typescript
   {
       totalCirculation: increment(-amount)  // Reduce circulante total
   }
   ```

### 3. **Generación del Hash de Transacción**

El **hash** es un identificador único e inmutable generado con **SHA-256** que sirve para:

- ✅ **Auditoría:** Verificar la integridad de la transacción
- ✅ **Inmutabilidad:** Garantizar que los datos no han sido modificados
- ✅ **Futura integración blockchain:** Preparado para verificación en blockchain

**Fórmula de generación:**
```typescript
const data = `${userId}|${amount}|${type}|${timestamp}|${beforeBalance}|${afterBalance}`;
const hash = SHA256(data).digest('hex');
```

**Ejemplo:**
```typescript
// Datos de entrada
userId: "abc123xyz"
amount: 5000
type: "admin_debit"
timestamp: 1705320600000
beforeBalance: 20000
afterBalance: 15000

// String concatenado
"abc123xyz|5000|admin_debit|1705320600000|20000|15000"

// Hash SHA-256 resultante
"4517b2378a0c96851e83f72426d07791f4a9d11fd0f51f4f88820738d..."
```

### 4. **Webhook N8N (Automático)**
Después de la transacción exitosa, se dispara automáticamente un webhook a N8N:

**URL del Webhook:**
```
https://versatec.app.n8n.cloud/webhook/70426eb0-aa5d-4f48-92f1-7d71fa8b6d3e
```

**Método:** GET  
**Parámetros (Query String):**

| Parámetro | Descripción | Ejemplo |
|-----------|-------------|---------|
| `event` | Tipo de evento | `admin_burn` |
| `type` | Tipo de operación | `WITHDRAWAL` |
| `targetUid` | ID del usuario afectado | `abc123xyz` |
| `amount` | Monto retirado | `5000` |
| `adminUid` | ID del admin que ejecutó | `admin123` |
| `timestamp` | Timestamp ISO | `2024-01-15T10:30:00.000Z` |

**Ejemplo de URL completa:**
```
https://versatec.app.n8n.cloud/webhook/70426eb0-aa5d-4f48-92f1-7d71fa8b6d3e?event=admin_burn&type=WITHDRAWAL&targetUid=abc123xyz&amount=5000&adminUid=admin123&timestamp=2024-01-15T10:30:00.000Z
```

---

## 📤 Respuesta de la Función

### Estructura de Respuesta Exitosa

```typescript
{
    success: true,
    newBalance: 15000,           // Nuevo balance del usuario
    transactionId: "tx_abc123"   // ID del registro en transaction_logs
}
```

### Errores Posibles

| Error | Causa | Solución |
|-------|-------|----------|
| `Authentication required` | No hay token de autenticación | Incluir token Firebase en headers |
| `Target UID required` | Falta `targetUid` | Proporcionar `targetUid` válido |
| `Invalid amount` | `amount` es 0 o negativo | Usar `amount > 0` |
| `User not found` | El `targetUid` no existe | Verificar que el usuario exista |
| `Insufficient user balance` | El usuario no tiene suficiente crédito | Verificar balance antes de retirar |

---

## 🔌 Integración con N8N

### Generar Hash en N8N

Si necesitas **generar el hash** en N8N (por ejemplo, para validar transacciones o crear registros manuales), puedes usar un **nodo Code/Function**:

**Nodo Code en N8N:**

```javascript
// Obtener datos de la transacción
const userId = $json.query.targetUid || $json.targetUid;
const amount = parseFloat($json.query.amount || $json.amount);
const type = "admin_debit";
const timestamp = Date.now(); // O usar $json.query.timestamp si está disponible
const beforeBalance = parseFloat($json.beforeBalance || 0);
const afterBalance = parseFloat($json.afterBalance || 0);

// Importar crypto (Node.js built-in)
const crypto = require('crypto');

// Concatenar datos en el mismo formato que Firebase
const dataString = `${userId}|${amount}|${type}|${timestamp}|${beforeBalance}|${afterBalance}`;

// Generar hash SHA-256
const hash = crypto.createHash('sha256').update(dataString).digest('hex');

// Retornar el hash junto con los datos originales
return {
    ...$json,
    transactionHash: hash,
    hashData: dataString, // Para debugging
    timestamp: timestamp
};
```

**Ejemplo con datos del webhook:**

```javascript
// Si recibes datos del webhook de Firebase
const userId = $json.query.targetUid;
const amount = parseFloat($json.query.amount);
const type = "admin_debit";
const timestamp = new Date($json.query.timestamp).getTime();
// Nota: beforeBalance y afterBalance no vienen en el webhook,
// necesitarías obtenerlos de Firestore o calcularlos

// Si tienes acceso a Firestore desde N8N
// const beforeBalance = await getBalanceFromFirestore(userId);
// const afterBalance = beforeBalance - amount;

const crypto = require('crypto');
const dataString = `${userId}|${amount}|${type}|${timestamp}|${beforeBalance}|${afterBalance}`;
const hash = crypto.createHash('sha256').update(dataString).digest('hex');

return {
    ...$json,
    transactionHash: hash
};
```

**Nota importante:** El hash generado en N8N **debe coincidir exactamente** con el hash que genera Firebase. Para que coincidan, necesitas:
- ✅ Mismo `userId`
- ✅ Mismo `amount`
- ✅ Mismo `type` ("admin_debit")
- ✅ Mismo `timestamp` (en milisegundos)
- ✅ Mismo `beforeBalance`
- ✅ Mismo `afterBalance`

### Opción 1: Llamar la Función desde N8N

Si N8N necesita **disparar** un BURN, puede llamar directamente a la función Firebase:

**Nodo HTTP Request en N8N:**

```json
{
    "method": "POST",
    "url": "https://[REGION]-[PROJECT-ID].cloudfunctions.net/adminWithdrawCreditsFunction",
    "headers": {
        "Content-Type": "application/json",
        "Authorization": "Bearer [FIREBASE_ID_TOKEN]"
    },
    "body": {
        "targetUid": "{{$json.userId}}",
        "amount": {{$json.amount}},
        "reason": "{{$json.reason}}"
    }
}
```

### Opción 2: Escuchar el Webhook Automático

Si N8N necesita **escuchar** cuando se ejecuta un BURN desde el dashboard, puede configurar un webhook listener:

**Nodo Webhook en N8N:**

1. **Tipo:** Webhook
2. **Método:** GET
3. **Path:** `/webhook/70426eb0-aa5d-4f48-92f1-7d71fa8b6d3e`
4. **Response Mode:** Respond to Webhook

**Filtro por tipo de evento:**
```javascript
// En un nodo IF después del webhook
if ($json.query.event === 'admin_burn' && $json.query.type === 'WITHDRAWAL') {
    return true;
}
return false;
```

**Datos disponibles en N8N:**
```json
{
    "query": {
        "event": "admin_burn",
        "type": "WITHDRAWAL",
        "targetUid": "abc123xyz",
        "amount": "5000",
        "adminUid": "admin123",
        "timestamp": "2024-01-15T10:30:00.000Z"
    }
}
```

**⚠️ Nota sobre el Hash:** El webhook **NO incluye** el hash ni los balances (`beforeBalance`, `afterBalance`). Si necesitas generar o validar el hash en N8N:

1. **Obtener balances desde Firestore** (usando nodo HTTP Request a Firestore REST API)
2. **Calcular:** `afterBalance = beforeBalance - amount`
3. **Generar hash** usando el código mostrado arriba

---

## 📊 Colecciones de Firestore Afectadas

### 1. `users/{targetUid}`
```typescript
{
    credit: newBalance,              // Balance actualizado
    lastUpdated: serverTimestamp()  // Última actualización
}
```

### 2. `transaction_logs/{transactionId}`
```typescript
{
    userId: targetUid,
    adminId: adminUid,
    amount: amount,
    type: "admin_debit",
    reason: reason,
    beforeBalance: currentBalance,
    afterBalance: newBalance,
    hash: transactionHash,
    metadata: { action: "burn_liquidity" },
    timestamp: serverTimestamp()
}
```

### 3. `financial_ledger/{ledgerId}`
```typescript
{
    type: "ADMIN_BURN",
    userId: targetUid,
    adminId: adminUid,
    amount: amount,
    description: reason,
    timestamp: serverTimestamp()
}
```

### 4. `system_stats/economy`
```typescript
{
    totalCirculation: increment(-amount)  // Se decrementa
}
```

---

## 🎯 Casos de Uso

### Caso 1: Cashout de Usuario
```json
{
    "targetUid": "user123",
    "amount": 10000,
    "reason": "Cashout usuario - Retiro de ganancias"
}
```

### Caso 2: Corrección de Balance
```json
{
    "targetUid": "user456",
    "amount": 500,
    "reason": "Corrección - Balance incorrecto detectado"
}
```

### Caso 3: Ajuste Administrativo
```json
{
    "targetUid": "user789",
    "amount": 2000,
    "reason": "Ajuste - Penalización por violación de términos"
}
```

---

## ⚠️ Consideraciones Importantes

1. **Irreversible:** Una vez ejecutado, el BURN no se puede revertir automáticamente. Si es necesario revertir, se debe hacer un MINT manual.

2. **Balance Mínimo:** La función verifica que el usuario tenga suficiente balance. Si no tiene suficiente, lanzará error.

3. **Transacción Atómica:** Todas las operaciones se ejecutan en una transacción atómica. Si algo falla, todo se revierte.

4. **Webhook No Bloqueante:** El webhook a N8N se ejecuta de forma asíncrona y no bloquea la respuesta de la función. Si el webhook falla, la transacción sigue siendo exitosa.

5. **Auditoría Completa:** Todas las operaciones se registran en `transaction_logs` y `financial_ledger` para auditoría.

---

## 🔍 Verificación Post-Ejecución

Después de ejecutar un BURN, puedes verificar:

1. **Balance del usuario:**
   ```javascript
   // Firestore
   users/{targetUid}.credit
   ```

2. **Registro en transaction_logs:**
   ```javascript
   // Buscar por userId y type: "admin_debit"
   transaction_logs.where('userId', '==', targetUid)
                   .where('type', '==', 'admin_debit')
                   .orderBy('timestamp', 'desc')
                   .limit(1)
   ```

3. **Registro en financial_ledger:**
   ```javascript
   // Buscar por userId y type: "ADMIN_BURN"
   financial_ledger.where('userId', '==', targetUid)
                   .where('type', '==', 'ADMIN_BURN')
                   .orderBy('timestamp', 'desc')
                   .limit(1)
   ```

4. **Circulante total:**
   ```javascript
   // Firestore
   system_stats/economy.totalCirculation
   ```

---

## 📝 Ejemplo Completo de Workflow N8N

### Workflow 1: Escuchar BURN y Generar Hash

1. **Webhook Trigger**
   - Escucha: `GET /webhook/70426eb0-aa5d-4f48-92f1-7d71fa8b6d3e`
   - Filtro: `event === 'admin_burn'`

2. **IF Node** (Validar tipo)
   ```javascript
   if ($json.query.type === 'WITHDRAWAL') {
       return true;
   }
   ```

3. **HTTP Request** (Obtener balance actual desde Firestore)
   ```json
   {
       "method": "GET",
       "url": "https://firestore.googleapis.com/v1/projects/poker-fa33a/databases/(default)/documents/users/{{$json.query.targetUid}}",
       "headers": {
           "Authorization": "Bearer {{$env.FIREBASE_ACCESS_TOKEN}}"
       }
   }
   ```
   **Nota:** Necesitas configurar un token de acceso de Firebase en las variables de entorno.

4. **Code Node** (Extraer balance y calcular)
   ```javascript
   const userId = $json.query.targetUid;
   const amount = parseFloat($json.query.amount);
   const beforeBalance = $('HTTP Request').item.json.fields.credit.integerValue || 
                        $('HTTP Request').item.json.fields.credit.doubleValue || 0;
   const afterBalance = beforeBalance - amount;
   const timestamp = new Date($json.query.timestamp).getTime();
   const type = "admin_debit";

   return {
       userId: userId,
       amount: amount,
       beforeBalance: beforeBalance,
       afterBalance: afterBalance,
       timestamp: timestamp,
       type: type,
       adminId: $json.query.adminUid,
       event: $json.query.event
   };
   ```

5. **Code Node** (Generar Hash)
   ```javascript
   const crypto = require('crypto');
   
   const userId = $json.userId;
   const amount = $json.amount;
   const type = $json.type;
   const timestamp = $json.timestamp;
   const beforeBalance = $json.beforeBalance;
   const afterBalance = $json.afterBalance;

   // Concatenar en el mismo formato que Firebase
   const dataString = `${userId}|${amount}|${type}|${timestamp}|${beforeBalance}|${afterBalance}`;
   
   // Generar hash SHA-256
   const hash = crypto.createHash('sha256').update(dataString).digest('hex');

   return {
       ...$json,
       transactionHash: hash,
       hashData: dataString // Para debugging/verificación
   };
   ```

6. **HTTP Request** (Opcional - Notificar a otro sistema con hash)
   ```json
   {
       "method": "POST",
       "url": "https://api.externa.com/notify",
       "body": {
           "event": "burn_executed",
           "userId": "{{$json.userId}}",
           "amount": {{$json.amount}},
           "transactionHash": "{{$json.transactionHash}}",
           "verified": true
       }
   }
   ```

### Workflow 2: Ejecutar BURN desde N8N y Validar Hash

1. **Trigger Manual** o **Schedule** (cuando necesites ejecutar un BURN)

2. **Code Node** (Preparar datos)
   ```javascript
   return {
       targetUid: "abc123xyz", // O desde input/previous node
       amount: 5000,
       reason: "Cashout usuario - Retiro de ganancias"
   };
   ```

3. **HTTP Request** (Llamar función Firebase)
   ```json
   {
       "method": "POST",
       "url": "https://[REGION]-[PROJECT-ID].cloudfunctions.net/adminWithdrawCreditsFunction",
       "headers": {
           "Content-Type": "application/json",
           "Authorization": "Bearer {{$env.FIREBASE_ID_TOKEN}}"
       },
       "body": {
           "targetUid": "{{$json.targetUid}}",
           "amount": {{$json.amount}},
           "reason": "{{$json.reason}}"
       }
   }
   ```

4. **HTTP Request** (Obtener transacción desde Firestore para validar hash)
   ```json
   {
       "method": "GET",
       "url": "https://firestore.googleapis.com/v1/projects/poker-fa33a/databases/(default)/documents/transaction_logs/{{$('HTTP Request').item.json.transactionId}}",
       "headers": {
           "Authorization": "Bearer {{$env.FIREBASE_ACCESS_TOKEN}}"
       }
   }
   ```

5. **Code Node** (Validar hash generado vs hash de Firestore)
   ```javascript
   const crypto = require('crypto');
   
   // Hash de Firestore
   const firestoreHash = $('HTTP Request').item.json.fields.hash.stringValue;
   
   // Datos de la transacción desde Firestore
   const userId = $('HTTP Request').item.json.fields.userId.stringValue;
   const amount = parseFloat($('HTTP Request').item.json.fields.amount.integerValue || 
                             $('HTTP Request').item.json.fields.amount.doubleValue);
   const type = $('HTTP Request').item.json.fields.type.stringValue;
   const timestamp = new Date($('HTTP Request').item.json.fields.timestamp.timestampValue).getTime();
   const beforeBalance = parseFloat($('HTTP Request').item.json.fields.beforeBalance.integerValue || 
                                    $('HTTP Request').item.json.fields.beforeBalance.doubleValue);
   const afterBalance = parseFloat($('HTTP Request').item.json.fields.afterBalance.integerValue || 
                                  $('HTTP Request').item.json.fields.afterBalance.doubleValue);

   // Regenerar hash
   const dataString = `${userId}|${amount}|${type}|${timestamp}|${beforeBalance}|${afterBalance}`;
   const calculatedHash = crypto.createHash('sha256').update(dataString).digest('hex');

   // Validar
   const isValid = firestoreHash === calculatedHash;

   return {
       transactionId: $('HTTP Request').item.json.name.split('/').pop(),
       firestoreHash: firestoreHash,
       calculatedHash: calculatedHash,
       isValid: isValid,
       hashData: dataString
   };
   ```

---

## 🔗 Funciones Relacionadas

- **MINT (Inyectar):** `adminMintCreditsFunction` - Aumenta créditos y circulante
- **BURN (Retirar):** `adminWithdrawCreditsFunction` - Reduce créditos y circulante

---

## 📞 Soporte

Para dudas o problemas con la integración:
- Revisar logs de Firebase Functions
- Verificar webhook en N8N
- Consultar `transaction_logs` para auditoría

---

**Última actualización:** 2024  
**Versión:** 1.0.0

