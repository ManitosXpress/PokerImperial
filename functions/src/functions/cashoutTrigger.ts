import * as functions from 'firebase-functions';
import { processCashOut } from './gameEconomy';

/**
 * ═══════════════════════════════════════════════════════════════════════════
 * CASHOUT TRIGGER - Procesador automático de cashouts iniciados por el servidor
 * ═══════════════════════════════════════════════════════════════════════════
 * 
 * Este trigger se activa cuando el Game Server escribe un documento en
 * _trigger_cashout/{docId}. Valida la firma HMAC y procesa el cashout de forma
 * segura, garantizando que la sesión se cierre y el dinero vuelva a la billetera.
 * 
 * IMPORTANTE: Este trigger es la solución al problema de "Sesiones Zombies".
 * El servidor puede forzar el cierre de sesión sin esperar a que el cliente responda.
 */

/**
 * Trigger: Activado cuando se crea un documento en _trigger_cashout
 * 
 * El documento debe contener:
 * - uid: ID del usuario
 * - tableId: ID de la mesa
 * - finalChips: Fichas finales del jugador
 * - reason: Razón del cashout (EXIT, DISCONNECT, BANKRUPTCY, TABLE_CLOSED)
 * - authPayload: Payload JSON firmado
 * - signature: Firma HMAC-SHA256
 * - timestamp: Timestamp del servidor
 */
export const onCashoutTriggered = functions.firestore
    .document('_trigger_cashout/{docId}')
    .onCreate(async (snap, context) => {
        const data = snap.data();
        const docId = context.params.docId;

        console.log(`[TRIGGER] 🔔 Cashout trigger activated for doc ${docId}`);
        console.log(`[TRIGGER] Data:`, { uid: data.uid, tableId: data.tableId, finalChips: data.finalChips, reason: data.reason });

        try {
            // Validación básica
            if (!data.uid || !data.tableId || !data.authPayload || !data.signature) {
                console.error(`[TRIGGER] ❌ Invalid trigger data - missing required fields`);
                await snap.ref.delete(); // Limpiar documento inválido
                return;
            }

            // Llamar a processCashOut con los datos firmados
            // No pasamos context.auth porque el servidor tiene autoridad total
            const result = await processCashOut({
                tableId: data.tableId,
                uid: data.uid,
                finalChips: Number(data.finalChips) || 0,
                reason: data.reason || 'server_initiated',
                authPayload: data.authPayload,
                signature: data.signature
            });

            if (result.success) {
                if (result.skipped) {
                    console.log(`[TRIGGER] ⚠️ Cashout skipped (already completed) for ${data.uid}`);
                } else {
                    console.log(`[TRIGGER] ✅ Cashout processed successfully for ${data.uid}: ${result.amount} chips`);
                }
            } else {
                console.error(`[TRIGGER] ❌ Cashout failed for ${data.uid}`);
            }

            // ✅ CRÍTICO: Borrar el documento trigger para evitar reprocesamiento
            await snap.ref.delete();
            console.log(`[TRIGGER] 🗑️ Trigger document ${docId} deleted`);

        } catch (error: any) {
            console.error(`[TRIGGER] ❌ Error processing cashout trigger:`, error);

            // Intentar borrar el documento de todos modos para evitar loops infinitos
            try {
                await snap.ref.delete();
                console.log(`[TRIGGER] 🗑️ Trigger document ${docId} deleted after error`);
            } catch (deleteError) {
                console.error(`[TRIGGER] ❌ Failed to delete trigger document:`, deleteError);
            }

            // No lanzar error para evitar reintentos infinitos
            // El error ya fue logueado
        }
    });
