import * as admin from 'firebase-admin';

/**
 * LOCAL SETTLEMENT UTILITY
 * 
 * Este módulo centraliza la lógica de liquidación de mesas de poker,
 * ejecutándola directamente en el servidor usando Admin SDK en lugar de
 * llamadas HTTP a Cloud Functions (que causan errores 401).
 * 
 * CRÍTICO: Esta lógica ejecuta transacciones atómicas en Firestore para
 * garantizar la integridad de datos financieros.
 */

/**
 * Guarda el estado actual del jugador en Firestore ANTES de liquidar
 * IMPORTANTE: Este es el "force save" que asegura que las fichas del jugador
 * estén sincronizadas en Firestore antes de ejecutar el cashout.
 * 
 * @param tableId - ID de la mesa de poker
 * @param playerUid - Firebase Auth UID del jugador
 * @param chips - Fichas actuales del jugador (según servidor de juego)
 * @returns true si se guardó exitosamente, false si hubo error
 */
export async function savePlayerStateToFirestore(
    tableId: string,
    playerUid: string,
    chips: number
): Promise<boolean> {
    try {
        const db = admin.firestore();
        const playerRef = db.collection('poker_tables').doc(tableId).collection('players').doc(playerUid);

        await playerRef.set({
            uid: playerUid,
            chips: chips,
            lastUpdated: admin.firestore.FieldValue.serverTimestamp()
        }, { merge: true });

        console.log(`✅ [SAVE_STATE] Player ${playerUid} state saved: ${chips} chips`);
        return true;
    } catch (error: any) {
        console.error(`❌ [SAVE_STATE] Failed to save player state for ${playerUid}:`, error);
        return false;
    }
}

/**
 * Ejecuta la liquidación completa de un jugador en una mesa
 * 
 * FLUJO:
 * 1. Lee las fichas finales desde Firestore (fuente de verdad)
 * 2. Busca la sesión activa del jugador
 * 3. Calcula el monto neto (fichas - exitFee, pero NO restar rake de nuevo)
 * 4. Actualiza balance del usuario
 * 5. Limpia moneyInPlay y currentTableId
 * 6. Registra en financial_ledger
 * 
 * @param tableId - ID de la mesa
 * @param playerUid - Firebase Auth UID del jugador
 * @param finalChips - Fichas finales (NETO, ya descontado el rake)
 * @param totalRakePaid - Total de rake pagado durante la sesión
 * @param reason - Razón de la salida
 * @returns true si la liquidación fue exitosa
 */
export async function performTableSettlement(
    tableId: string,
    playerUid: string,
    finalChips: number,
    totalRakePaid: number,
    reason: 'EXIT' | 'DISCONNECT' | 'BANKRUPTCY' | 'TABLE_CLOSED'
): Promise<boolean> {
    if (!admin.apps.length) {
        console.error('[SETTLEMENT] ❌ Firebase Admin not initialized');
        return false;
    }

    const db = admin.firestore();

    console.log(`[SETTLEMENT] 🎯 Iniciando liquidación para ${playerUid} en mesa ${tableId}`);
    console.log(`[SETTLEMENT] Fichas finales: ${finalChips}, Rake pagado: ${totalRakePaid}, Razón: ${reason}`);

    try {
        await db.runTransaction(async (transaction) => {
            const userRef = db.collection('users').doc(playerUid);

            // 1. BUSCAR SESIÓN ACTIVA
            const sessionsQuery = await db.collection('poker_sessions')
                .where('userId', '==', playerUid)
                .where('roomId', '==', tableId)
                .where('status', '==', 'active')
                .orderBy('startTime', 'desc')
                .limit(1)
                .get();

            if (sessionsQuery.empty) {
                console.warn(`⚠️ [SETTLEMENT] No active session found for ${playerUid} in table ${tableId}`);
                // Continuar de todos modos para limpiar estado del usuario
            }

            const sessionDoc = sessionsQuery.empty ? null : sessionsQuery.docs[0];
            const sessionRef = sessionDoc ? db.collection('poker_sessions').doc(sessionDoc.id) : null;
            const sessionData = sessionDoc?.data();

            // 2. LEER FICHAS DESDE FIRESTORE (FUENTE DE VERDAD)
            // Si el parámetro finalChips viene del servidor, podría estar desactualizado
            let actualFinalChips = finalChips;

            const tableRef = db.collection('poker_tables').doc(tableId);
            const tableDoc = await transaction.get(tableRef);

            if (tableDoc.exists) {
                const tableData = tableDoc.data();
                const players = Array.isArray(tableData?.players) ? tableData.players : [];
                const playerInTable = players.find((p: any) => p.id === playerUid || p.uid === playerUid);

                if (playerInTable && playerInTable.chips !== undefined) {
                    actualFinalChips = Number(playerInTable.chips) || 0;
                    console.log(`[SETTLEMENT] ✅ Fichas leídas de Firestore: ${actualFinalChips} (servidor reportó: ${finalChips})`);
                }
            }

            // 3. LEER DATOS DEL USUARIO
            const userDoc = await transaction.get(userRef);
            if (!userDoc.exists) {
                throw new Error(`User ${playerUid} not found`);
            }

            const userData = userDoc.data();
            const displayName = userData?.displayName || 'Unknown';
            const buyInAmount = Number(sessionData?.buyInAmount) || 0;

            // 4. CALCULAR MONTO NETO
            const exitFee = 0; // Por ahora sin exit fee
            const netWinnings = Math.max(0, actualFinalChips - exitFee);
            const netProfit = netWinnings - buyInAmount;

            console.log(`[SETTLEMENT] Usuario: ${displayName}`);
            console.log(`[SETTLEMENT] Buy-in original: ${buyInAmount}`);
            console.log(`[SETTLEMENT] Fichas finales: ${actualFinalChips}`);
            console.log(`[SETTLEMENT] Rake pagado (acumulado): ${totalRakePaid}`);
            console.log(`[SETTLEMENT] Monto neto a transferir: ${netWinnings}`);
            console.log(`[SETTLEMENT] Ganancia/Pérdida: ${netProfit > 0 ? '+' : ''}${netProfit}`);

            // 5. ACTUALIZAR SESIÓN (si existe)
            if (sessionRef) {
                transaction.update(sessionRef, {
                    currentChips: actualFinalChips,
                    totalRakePaid: totalRakePaid,
                    exitFee: exitFee,
                    netResult: netWinnings,
                    endTime: admin.firestore.FieldValue.serverTimestamp(),
                    status: 'completed'
                });
            }

            // 6. ACTUALIZAR BALANCE DEL USUARIO
            const userUpdate: any = {
                moneyInPlay: 0, // ✅ CRÍTICO: Limpiar dinero en juego
                currentTableId: null, // ✅ CRÍTICO: Limpiar mesa actual
                lastUpdated: admin.firestore.FieldValue.serverTimestamp()
            };

            if (netWinnings > 0) {
                userUpdate.credit = admin.firestore.FieldValue.increment(netWinnings);
                console.log(`[SETTLEMENT] ✅ Crédito actualizado: +${netWinnings}`);
            }

            transaction.update(userRef, userUpdate);
            console.log(`[SETTLEMENT] ✅ Estado visual limpiado: moneyInPlay=0, currentTableId=null`);

            const timestamp = admin.firestore.FieldValue.serverTimestamp();

            // 7. REGISTRAR RAKE EN PLATAFORMA (si hay)
            if (totalRakePaid > 0) {
                const statsRef = db.collection('system_stats').doc('economy');
                transaction.set(statsRef, {
                    accumulated_rake: admin.firestore.FieldValue.increment(totalRakePaid),
                    lastUpdated: timestamp
                }, { merge: true });

                console.log(`[SETTLEMENT] ✅ Rake registrado en plataforma: +${totalRakePaid}`);

                // Registrar rake en ledger financiero
                const rakeLedgerRef = db.collection('financial_ledger').doc();
                transaction.set(rakeLedgerRef, {
                    type: 'RAKE_COLLECTED',
                    userId: playerUid,
                    userName: displayName,
                    tableId: tableId,
                    amount: totalRakePaid,
                    timestamp: timestamp,
                    description: `Rake collected during session (${totalRakePaid} chips)`
                });
            }

            // 8. REGISTRAR SESSION_END EN LEDGER
            const ledgerRef = db.collection('financial_ledger').doc();
            transaction.set(ledgerRef, {
                type: 'SESSION_END',
                userId: playerUid,
                userName: displayName,
                tableId: tableId,
                amount: netWinnings,
                profit: netProfit,
                grossAmount: actualFinalChips,
                buyInAmount: buyInAmount,
                rakePaid: totalRakePaid,
                exitFee: exitFee,
                timestamp: timestamp,
                reason: reason,
                description: `Session ended (${reason}). Final chips: ${actualFinalChips}, Buy-in: ${buyInAmount}, Net: ${netProfit > 0 ? '+' : ''}${netProfit}`
            });

            // 9. REGISTRAR EN TRANSACTION LOGS (para UI de wallet)
            if (netWinnings > 0) {
                const transactionRef = userRef.collection('transactions').doc();
                transaction.set(transactionRef, {
                    type: 'poker_cashout',
                    amount: netWinnings,
                    reason: `Poker Cashout${netProfit >= 0 ? ' - Winner' : ' - Loss'}`,
                    sessionId: sessionRef?.id || null,
                    metadata: {
                        finalChips: actualFinalChips,
                        buyInAmount: buyInAmount,
                        netProfit: netProfit,
                        rakePaid: totalRakePaid,
                        exitFee: exitFee,
                        reason: reason
                    },
                    timestamp: timestamp
                });

                const logRef = db.collection('transaction_logs').doc();
                transaction.set(logRef, {
                    userId: playerUid,
                    amount: netWinnings,
                    type: 'credit',
                    reason: `Poker Cashout - ${tableId}`,
                    timestamp: timestamp,
                    beforeBalance: userData?.credit || 0,
                    afterBalance: (userData?.credit || 0) + netWinnings,
                    metadata: {
                        sessionId: sessionRef?.id || null,
                        tableId: tableId,
                        finalChips: actualFinalChips,
                        buyInAmount: buyInAmount,
                        profit: netProfit
                    }
                });
            }
        });

        console.log(`✅ [SETTLEMENT] Liquidación completada exitosamente para ${playerUid}`);
        return true;

    } catch (error: any) {
        console.error(`❌ [SETTLEMENT] Error en liquidación para ${playerUid}:`, error);
        console.error(`❌ [SETTLEMENT] Mensaje: ${error.message}`);
        console.error(`❌ [SETTLEMENT] Stack: ${error.stack}`);
        return false;
    }
}

/**
 * Wrapper de performTableSettlement para compatibilidad con código existente
 * Busca automáticamente el totalRakePaid desde la sesión activa
 */
export async function performTableSettlementAuto(
    tableId: string,
    playerUid: string,
    finalChips: number,
    reason: 'EXIT' | 'DISCONNECT' | 'BANKRUPTCY' | 'TABLE_CLOSED'
): Promise<boolean> {
    const db = admin.firestore();

    try {
        // Buscar rake acumulado en la sesión
        const sessionsQuery = await db.collection('poker_sessions')
            .where('userId', '==', playerUid)
            .where('roomId', '==', tableId)
            .where('status', '==', 'active')
            .orderBy('startTime', 'desc')
            .limit(1)
            .get();

        const totalRakePaid = sessionsQuery.empty ? 0 : (sessionsQuery.docs[0].data()?.totalRakePaid || 0);

        return await performTableSettlement(tableId, playerUid, finalChips, totalRakePaid, reason);
    } catch (error) {
        console.error(`❌ [SETTLEMENT_AUTO] Error:`, error);
        return false;
    }
}
