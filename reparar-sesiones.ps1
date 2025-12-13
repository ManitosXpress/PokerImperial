# Script de Reparacion de Sesiones Stuck - PowerShell
# Proyecto: poker-fa33a

$projectId = "poker-fa33a"
$region = "us-central1"  # Cambia esto si tus funciones estan en otra region
$functionName = "repairStuckSessions"

# Construir la URL de la funcion
$url = "https://$region-$projectId.cloudfunctions.net/$functionName"

Write-Host "[REPARACION] Ejecutando script de reparacion de sesiones stuck..." -ForegroundColor Cyan
Write-Host "[INFO] Proyecto: $projectId" -ForegroundColor Yellow
Write-Host "[INFO] Region: $region" -ForegroundColor Yellow
Write-Host "[INFO] URL: $url" -ForegroundColor Yellow
Write-Host ""

try {
    # Realizar la peticion POST
    $response = Invoke-RestMethod -Uri $url -Method Post -ContentType "application/json" -Body "{}"
    
    Write-Host "[OK] Reparacion completada exitosamente!" -ForegroundColor Green
    Write-Host ""
    Write-Host "[RESUMEN]" -ForegroundColor Cyan
    Write-Host "   - Total de sesiones analizadas: $($response.summary.total)" -ForegroundColor White
    Write-Host "   - Sesiones reparadas: $($response.summary.repaired)" -ForegroundColor Green
    Write-Host "   - Sesiones omitidas (validas): $($response.summary.skipped)" -ForegroundColor Yellow
    Write-Host "   - Errores: $($response.summary.errors)" -ForegroundColor $(if ($response.summary.errors -gt 0) { "Red" } else { "Green" })
    Write-Host ""
    
    if ($response.details.Count -gt 0) {
        Write-Host "[DETALLES] Detalles de las reparaciones:" -ForegroundColor Cyan
        $repairedSessions = $response.details | Where-Object { $_.status -eq "repaired" }
        
        if ($repairedSessions.Count -gt 0) {
            Write-Host ""
            foreach ($session in $repairedSessions) {
                Write-Host "   [OK] Sesion: $($session.sessionId)" -ForegroundColor Green
                Write-Host "      Usuario: $($session.userId)" -ForegroundColor Gray
                Write-Host "      Mesa: $($session.roomId)" -ForegroundColor Gray
                Write-Host "      Buy-in: $($session.buyInAmount)" -ForegroundColor Gray
                Write-Host ""
            }
        }
    }
    
    # Convertir respuesta a JSON formateado para mostrar completo
    Write-Host "[JSON] Respuesta completa:" -ForegroundColor Cyan
    $response | ConvertTo-Json -Depth 10 | Write-Host
    
} catch {
    Write-Host "[ERROR] Error al ejecutar el script:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    
    # Si es un error 404, sugerir verificar la region
    if ($_.Exception.Response.StatusCode.value__ -eq 404) {
        Write-Host "[SUGERENCIA] Verifica que la region sea correcta." -ForegroundColor Yellow
        Write-Host "   Regiones comunes: us-central1, us-east1, europe-west1, asia-east1" -ForegroundColor Yellow
        Write-Host "   Puedes verificar la region en Firebase Console > Functions" -ForegroundColor Yellow
    }
    
    exit 1
}

Write-Host ""
Write-Host "[COMPLETADO] Proceso completado!" -ForegroundColor Green

