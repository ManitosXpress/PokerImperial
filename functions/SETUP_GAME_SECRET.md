# Configuración de Firebase Secret para GAME_SECRET

## Opción 1: Usar Firebase Functions Config (Método Legacy - Más Simple)

```bash
# Configurar el secret
firebase functions:config:set game.secret="tu-secret-super-seguro-aqui-2024"

# Ver la configuración actual
firebase functions:config:get

# Redesplegar las funciones para que tome el cambio
firebase deploy --only functions
```

## Opción 2: Usar Firebase Secrets Manager (Recomendado para Producción)

```bash
# 1. Crear el secret en Google Cloud Secret Manager
firebase functions:secrets:set GAME_SECRET

# Te pedirá que ingreses el valor del secret
# Ingresa: tu-secret-super-seguro-aqui-2024

# 2. Permitir que las funciones accedan al secret
# (Esto se hace automáticamente con el comando anterior)

# 3. Actualizar el código para usar el secret (ya está configurado)

# 4. Redesplegar
firebase deploy --only functions
```

## IMPORTANTE: Sincronización con el Game Server

El `GAME_SECRET` debe ser **EXACTAMENTE EL MISMO** en:
- Firebase Functions (Producción)
- Game Server Node.js (`server/src/config.ts` o `.env`)

Usa el mismo valor en ambos lados para que la verificación HMAC funcione.

## Valor Recomendado

Genera un secret seguro con:

```bash
# En PowerShell
-join ((48..57) + (65..90) + (97..122) | Get-Random -Count 32 | ForEach-Object {[char]$_})

# O usa un generador online (UUID también sirve)
```

Ejemplo de secret seguro:
```
aB3dF7k9mP2qR5sT8vW1xY4zA6bC9eD
```
