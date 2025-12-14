# 🧹 Script de Limpieza de Base de Datos

Este script elimina **todas las colecciones de Firestore EXCEPTO la colección `users`**, preservando completamente los usuarios y sus créditos.

## ⚠️ ADVERTENCIA IMPORTANTE

- **Esta operación es IRREVERSIBLE**
- Se eliminarán TODAS las colecciones excepto `users`
- Los usuarios y sus créditos se mantendrán intactos
- Se eliminarán: sesiones, transacciones, mesas, torneos, estadísticas, etc.

## 📋 Requisitos Previos

1. **Autenticación con Firebase (elige UNA de estas opciones):**

   **Opción A: Firebase CLI (Recomendado para desarrollo)**
   ```bash
   npm install -g firebase-tools
   firebase login
   ```

   **Opción B: Service Account Key (Recomendado para producción)**
   - Ve a: https://console.firebase.google.com/project/poker-fa33a/settings/serviceaccounts/adminsdk
   - Haz clic en "Generar nueva clave privada"
   - Guarda el archivo JSON como `serviceAccountKey.json` en la raíz del proyecto
   - O colócalo en el directorio `server/`

2. **Node.js instalado** (versión 18 o superior)

3. **Dependencias del proyecto:**
   ```bash
   npm install
   ```

## 🚀 Cómo Usar el Script

### Opción 1: Ejecutar directamente

```bash
node clean-database.js
```

### Opción 2: Ejecutar desde la raíz del proyecto

```bash
cd E:\Poker
node clean-database.js
```

## 📝 Proceso de Ejecución

1. **El script pedirá confirmación dos veces:**
   - Primera confirmación: Escribe `SI` (en mayúsculas)
   - Segunda confirmación: Escribe `ELIMINAR` (en mayúsculas)

2. **El script mostrará:**
   - Lista de colecciones encontradas
   - Colecciones que serán preservadas (`users`)
   - Colecciones que serán eliminadas
   - Progreso de eliminación en tiempo real
   - Resumen final con estadísticas

## 📊 Qué se Preserva

✅ **Colección `users`:**
- Todos los documentos de usuarios
- Todos los créditos (`credit`)
- Todos los datos de perfil
- Sub-colecciones dentro de usuarios (si existen)

## 🗑️ Qué se Elimina

❌ **Todas las demás colecciones, incluyendo:**
- `financial_ledger` (registros financieros)
- `transaction_logs` (logs de transacciones)
- `poker_sessions` (sesiones de poker)
- `poker_tables` (mesas de poker)
- `tournaments` (torneos)
- `stats_daily` (estadísticas diarias)
- `clubs` (clubes)
- `invitations` (invitaciones)
- Y cualquier otra colección que exista

## 📈 Ejemplo de Salida

```
🧹 SCRIPT DE LIMPIEZA DE BASE DE DATOS
======================================================================

⚠️  ADVERTENCIA: Esta operación eliminará TODAS las colecciones
   EXCEPTO la colección "users" que será preservada completamente.
   Esta operación es IRREVERSIBLE!

¿Estás seguro de que quieres continuar? (escribe "SI" para confirmar): SI

⚠️  Última confirmación. Escribe "ELIMINAR" para proceder: ELIMINAR

🚀 Iniciando limpieza de base de datos...

📋 Colecciones encontradas: users, financial_ledger, poker_sessions, poker_tables

✅ Colección preservada: users
   - Usuarios preservados: 15
   - Todos los créditos y datos de usuarios se mantienen intactos

🗑️  Colecciones a eliminar: financial_ledger, poker_sessions, poker_tables

🗑️  Eliminando colección: financial_ledger
   ✅ Procesados 150 documentos de financial_ledger...
✅ Colección financial_ledger eliminada completamente (150 documentos incluyendo sub-colecciones)

...

======================================================================
✅ LIMPIEZA COMPLETADA
======================================================================
   📊 Colecciones procesadas: 3
   ✅ Colecciones eliminadas exitosamente: 3
   ❌ Errores: 0
   🗑️  Total de documentos eliminados: 450
   👥 Usuarios preservados: Sí (colección "users" intacta)
======================================================================
```

## 🔒 Seguridad

- El script requiere **doble confirmación** antes de ejecutar
- No se puede ejecutar accidentalmente
- Muestra claramente qué se preservará y qué se eliminará

## 🐛 Solución de Problemas

### Error: "Could not load the default credentials"
**Solución 1: Usar Firebase CLI**
```bash
firebase login
```

**Solución 2: Usar Service Account Key**
1. Ve a: https://console.firebase.google.com/project/poker-fa33a/settings/serviceaccounts/adminsdk
2. Haz clic en "Generar nueva clave privada"
3. Guarda el archivo como `serviceAccountKey.json` en la raíz del proyecto
4. Ejecuta el script nuevamente

### Error: "Firebase Admin not initialized"
- Asegúrate de estar autenticado: `firebase login`
- O coloca `serviceAccountKey.json` en la raíz del proyecto
- Verifica que el proyecto sea `poker-fa33a`

### Error: "Permission denied"
- Verifica que tengas permisos de administrador en Firebase
- Asegúrate de estar autenticado correctamente
- Si usas serviceAccountKey.json, verifica que tenga los permisos correctos

### El script se detiene a mitad de camino
- Algunos datos pueden haber sido eliminados
- Revisa los logs para ver qué se eliminó
- Puedes ejecutar el script nuevamente (solo eliminará lo que quede)

## 📞 Soporte

Si encuentras problemas o necesitas ayuda, revisa:
- Los logs del script
- La consola de Firebase: https://console.firebase.google.com/project/poker-fa33a/firestore
- El código del script en `clean-database.js`

## ⚡ Notas Técnicas

- El script procesa documentos en lotes de 500 para evitar timeouts
- Elimina sub-colecciones recursivamente
- Muestra progreso en tiempo real
- Maneja errores de forma segura

