# 🔧 Script de Reparación de Sesiones Stuck

## 📋 Problema

Cuando una mesa se cierra, a veces el indicador **"+X en mesa"** sigue apareciendo en el badge de la billetera. Esto ocurre porque:

1. La sesión de poker tiene `status: 'active'` pero ya tiene `endTime` (inconsistencia)
2. La sesión está marcada como 'active' pero el usuario no está en ninguna mesa activa
3. La mesa fue eliminada pero la sesión quedó huérfana

## ✅ Solución

El script `repairStuckSessions` detecta y repara automáticamente estas sesiones:

- ✅ Sesiones con `endTime` pero `status: 'active'` (inconsistencias)
- ✅ Sesiones huérfanas (mesa no existe)
- ✅ Sesiones donde el usuario no está en mesa activa
- ✅ Limpia los campos `currentTableId` y `moneyInPlay` del usuario

## 🚀 Uso del Script

### Opción 1: Desde la Terminal (cURL)

```bash
curl -X POST https://YOUR_REGION-YOUR_PROJECT.cloudfunctions.net/repairStuckSessions \
  -H "Content-Type: application/json" \
  -d '{}'
```

### Opción 2: Desde el Navegador (POST Request)

1. Abre las **DevTools** (F12)
2. Ve a la pestaña **Console**
3. Ejecuta:

```javascript
fetch('https://YOUR_REGION-YOUR_PROJECT.cloudfunctions.net/repairStuckSessions', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json'
  },
  body: JSON.stringify({})
})
.then(res => res.json())
.then(data => console.log('Resultado:', data))
.catch(err => console.error('Error:', err));
```

### Opción 3: Desde Postman o Insomnia

- **URL:** `https://YOUR_REGION-YOUR_PROJECT.cloudfunctions.net/repairStuckSessions`
- **Método:** `POST`
- **Headers:** `Content-Type: application/json`
- **Body:** `{}` (vacío)

## 📊 Respuesta del Script

```json
{
  "success": true,
  "summary": {
    "total": 5,
    "repaired": 3,
    "skipped": 1,
    "errors": 1
  },
  "details": [
    {
      "userId": "user123",
      "sessionId": "session456",
      "roomId": "room789",
      "buyInAmount": 1000,
      "currentChips": 1000,
      "status": "repaired"
    },
    {
      "userId": "user456",
      "sessionId": "session789",
      "roomId": "room123",
      "buyInAmount": 500,
      "currentChips": 500,
      "status": "skipped"
    }
  ]
}
```

## 🔍 Qué Hace el Script

### 1. Detecta Sesiones Inconsistentes
- Busca sesiones con `status: 'active'` pero que tienen `endTime`
- Las marca como `status: 'completed'`
- Limpia los indicadores visuales del usuario

### 2. Detecta Sesiones Huérfanas
- Sesiones donde la mesa no existe
- Devuelve el dinero al usuario
- Cierra la sesión correctamente

### 3. Detecta Sesiones Stuck
- Sesiones donde el usuario no está en ninguna mesa activa
- Devuelve el dinero al usuario
- Cierra la sesión y limpia indicadores

## ⚠️ Notas Importantes

1. **El script es seguro:** Solo repara sesiones que realmente están stuck
2. **No afecta sesiones válidas:** Si el usuario está en una mesa activa, la sesión se omite
3. **Devuelve el dinero:** En caso de sesiones huérfanas, devuelve el `buyInAmount` o `currentChips` (el mayor)
4. **Registra en ledger:** Todas las reparaciones se registran en `financial_ledger` con tipo `REPAIR_REFUND`

## 🔄 Ejecución Periódica (Opcional)

Puedes configurar un cron job o Cloud Scheduler para ejecutar el script periódicamente:

```bash
# Ejecutar cada hora
0 * * * * curl -X POST https://YOUR_REGION-YOUR_PROJECT.cloudfunctions.net/repairStuckSessions -H "Content-Type: application/json" -d '{}'
```

## 📝 Logs

El script genera logs detallados en Cloud Functions:

```
🔧 Iniciando reparación de sesiones atascadas...
📊 Encontradas 5 sesiones con status 'active'
⚠️ Encontradas 2 sesiones inconsistentes (status 'active' pero con endTime)
🔧 Reparando sesión inconsistente: session123 (tiene endTime pero status 'active')
⚠️ Sesión huérfana encontrada: session456 (Mesa room789 no existe)
⚠️ Sesión atascada encontrada: session789 (Usuario no en mesa activa)
✅ Reparación completada:
   - Reparadas: 3
   - Omitidas (válidas): 1
   - Errores: 1
```

## 🛠️ Troubleshooting

### El script no encuentra sesiones stuck
- Verifica que las sesiones realmente tengan `status: 'active'`
- Revisa los logs de Cloud Functions

### El indicador sigue apareciendo después de ejecutar
- Refresca la página de la aplicación
- Verifica que el stream de `inGameBalance` se actualice
- Ejecuta el script nuevamente

### Error 405 (Method Not Allowed)
- Asegúrate de usar `POST` (no `GET`)
- Verifica que la URL sea correcta

## 📞 Soporte

Si el problema persiste después de ejecutar el script, verifica:

1. Que las Cloud Functions estén desplegadas correctamente
2. Que tengas permisos para ejecutar funciones HTTP
3. Los logs de Cloud Functions para ver errores específicos

