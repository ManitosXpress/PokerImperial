# 🔧 Reparar Sesiones Stuck - PowerShell

## 🚀 Uso Rápido

### Opción 1: Ejecutar el Script (Recomendado)

```powershell
.\reparar-sesiones.ps1
```

### Opción 2: Comando Directo

```powershell
Invoke-RestMethod -Uri "https://us-central1-poker-fa33a.cloudfunctions.net/repairStuckSessions" -Method Post -ContentType "application/json" -Body "{}"
```

## 📋 Verificar la Región

Si el comando falla con error 404, necesitas verificar la región de tus funciones:

1. Ve a [Firebase Console](https://console.firebase.google.com/project/poker-fa33a/functions)
2. Abre la pestaña **Functions**
3. Busca la función `repairStuckSessions`
4. Verifica la región en la URL o en los detalles

### Regiones Comunes:
- `us-central1` (Iowa, USA) - **Por defecto**
- `us-east1` (Carolina del Sur, USA)
- `europe-west1` (Bélgica)
- `asia-east1` (Taiwán)

## 🔧 Modificar el Script

Si tus funciones están en otra región, edita `reparar-sesiones.ps1`:

```powershell
$region = "us-east1"  # Cambia aquí la región
```

## 📊 Ejemplo de Salida

```
🔧 Ejecutando script de reparación de sesiones stuck...
📋 Proyecto: poker-fa33a
🌍 Región: us-central1
🔗 URL: https://us-central1-poker-fa33a.cloudfunctions.net/repairStuckSessions

✅ Reparación completada exitosamente!

📊 Resumen:
   - Total de sesiones analizadas: 5
   - Sesiones reparadas: 3
   - Sesiones omitidas (válidas): 1
   - Errores: 1

📝 Detalles de las reparaciones:

   ✅ Sesión: session123
      Usuario: user456
      Mesa: room789
      Buy-in: 1000
```

## ⚠️ Solución de Problemas

### Error: "No se puede invocar el método"
```powershell
# Ejecuta PowerShell como Administrador o cambia la política de ejecución:
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Error 404: Función no encontrada
- Verifica que la función esté desplegada
- Verifica que la región sea correcta
- Verifica que el nombre de la función sea `repairStuckSessions`

### Error 405: Method Not Allowed
- Asegúrate de usar `-Method Post`
- Verifica que el body sea `"{}"` (JSON vacío)

## 🔄 Automatización

Puedes crear una tarea programada en Windows para ejecutar esto periódicamente:

```powershell
# Crear tarea programada (ejecutar cada hora)
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-File C:\ruta\a\reparar-sesiones.ps1"
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 365)
Register-ScheduledTask -TaskName "RepararSesionesStuck" -Action $action -Trigger $trigger
```

## 📞 Más Información

Ver `REPARAR_SESIONES_STUCK.md` para detalles completos del script.

