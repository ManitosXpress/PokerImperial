import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { SettleRoundRequest } from "../types";

/**
 * settleGameRound
 * 
 * ALGORITMO ESTRICTO Y SECUENCIAL PARA LIQUIDACIÓN DE RONDAS
 * 
 * Garantiza integridad financiera mediante el siguiente flujo:
 * 
 * Paso 1: Cálculo del Bote y Rake (EN MEMORIA)
 * Paso 2: Distribución del Rake (ESCRIBIR EN BD)
 * Paso 3: Asignación al Ganador (ACTUALIZAR STACK EN MESA)
 * Paso 4: Cashout / Liquidación (TRANSFERIR A BILLETERA)
 * Paso 5: Historial (Ledger)
 * 
 * CRÍTICO: Primero se suma el bote al stack, luego se cobra el rake, y al final se transfiere a la billetera.
 */
export const settleGameRound = async (data: SettleRoundRequest, context: functions.https.CallableContext) => {
    const db = admin.firestore();

    // 1. Validación
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'The function must be called while authenticated.');
    }

    const { potTotal, winnerUid, playersInvolved, gameId, tableId } = data;

    if (!potTotal || !winnerUid || !playersInvolved || playersInvolved.length === 0 || !tableId) {
        throw new functions.https.HttpsError('invalid-argument', 'Missing required parameters: potTotal, winnerUid, playersInvolved, tableId.');
    }

    const timestamp = admin.firestore.Timestamp.now();
    const RAKE_PERCENTAGE = 0.08;

    // ============================================
    // PASO 1: CÁLCULO DEL BOTE Y RAKE (EN MEMORIA)
    // ============================================
    const totalPot = potTotal; // Suma de todas las apuestas
    const rakeAmount = Math.floor(totalPot * RAKE_PERCENTAGE); // 8% del bote
    const winnerPrize = totalPot - rakeAmount; // Premio neto que se lleva el ganador

    console.log(`[SETTLE_ROUND] Paso 1 - Pot Total: ${totalPot}, Rake Calculado: ${rakeAmount}, Premio Neto: ${winnerPrize}`);

    // Buscar sesión activa del ganador ANTES de la transacción (las queries no se pueden hacer dentro de transacciones)
    const activeSessionsQuery = await db.collection('poker_sessions')
        .where('userId', '==', winnerUid)
        .where('roomId', '==', tableId)
        .where('status', '==', 'active')
        .limit(1)
        .get();

    let winnerSessionRef: admin.firestore.DocumentReference | null = null;
    if (!activeSessionsQuery.empty) {
        winnerSessionRef = activeSessionsQuery.docs[0].ref;
        console.log(`[SETTLE_ROUND] Sesión activa encontrada para ganador: ${activeSessionsQuery.docs[0].id}`);
        
        // Si hay múltiples sesiones activas, registrar advertencia
        if (activeSessionsQuery.size > 1) {
            console.warn(`[SETTLE_ROUND] ⚠️ ADVERTENCIA: Se encontraron ${activeSessionsQuery.size} sesiones activas para ${winnerUid} en mesa ${tableId}. Esto puede causar problemas.`);
        }
    } else {
        console.warn(`[SETTLE_ROUND] No se encontró sesión activa para ganador ${winnerUid} en mesa ${tableId}`);
    }

    // 4. Ejecutar Transacción Atómica
    try {
        await db.runTransaction(async (transaction) => {
            // Leer mesa para obtener información (isPublic, players)
            const tableRef = db.collection('poker_tables').doc(tableId);
            const tableDoc = await transaction.get(tableRef);
            
            if (!tableDoc.exists) {
                throw new functions.https.HttpsError('not-found', `Table ${tableId} not found.`);
            }

            const tableData = tableDoc.data();
            const isPublic = tableData?.isPublic === true;
            const players = Array.isArray(tableData?.players) ? [...tableData.players] : [];

            // Encontrar el jugador ganador en la mesa
            const winnerPlayerIndex = players.findIndex((p: any) => p.id === winnerUid);
            if (winnerPlayerIndex === -1) {
                throw new functions.https.HttpsError('not-found', `Winner ${winnerUid} not found in table players.`);
            }

            const winnerPlayer = players[winnerPlayerIndex];
            const currentWinnerChips = Number(winnerPlayer.chips) || 0;

            console.log(`[SETTLE_ROUND] Mesa ${tableId} - Pública: ${isPublic}, Chips actuales del ganador: ${currentWinnerChips}`);

            // Leer datos del ganador
            const winnerRef = db.collection('users').doc(winnerUid);
            const winnerDoc = await transaction.get(winnerRef);
            if (!winnerDoc.exists) {
                throw new functions.https.HttpsError('not-found', `Winner user ${winnerUid} not found.`);
            }

            const winnerData = winnerDoc.data();
            const winnerClubId = winnerData?.clubId;
            const winnerSellerId = winnerData?.sellerId;

            // ============================================
            // PASO 2: DISTRIBUCIÓN DEL RAKE (ESCRIBIR EN BD)
            // ============================================
            let platformProfit = 0;
            let clubProfit = 0;
            let sellerProfit = 0;
            let targetClubId: string | null = null;
            let targetSellerId: string | null = null;

            if (!isPublic) {
                // Sala Privada: 100% del rake va a la plataforma
                platformProfit = rakeAmount;
                console.log(`[SETTLE_ROUND] Paso 2 - Sala Privada: PlatformProfit = ${platformProfit}`);
            } else {
                // Sala Pública: Distribución 50-30-20
                platformProfit = Math.floor(rakeAmount * 0.50);
                clubProfit = Math.floor(rakeAmount * 0.30);
                sellerProfit = Math.floor(rakeAmount * 0.20);
                
                // Ajustar por redondeo
                const remainder = rakeAmount - (platformProfit + clubProfit + sellerProfit);
                platformProfit += remainder;

                targetClubId = winnerClubId || null;
                targetSellerId = winnerSellerId || null;

                // Si no hay seller, el 20% va al club
                if (!targetSellerId && targetClubId) {
                    clubProfit += sellerProfit;
                    sellerProfit = 0;
                } else if (!targetSellerId && !targetClubId) {
                    // Si no hay club ni seller, todo va a la plataforma
                    platformProfit += clubProfit + sellerProfit;
                    clubProfit = 0;
                    sellerProfit = 0;
                }

                console.log(`[SETTLE_ROUND] Paso 2 - Sala Pública: PlatformProfit = ${platformProfit}, ClubProfit = ${clubProfit}, SellerProfit = ${sellerProfit}`);
            }

            // Actualizar billeteras de Admin, Club y Seller
            if (platformProfit > 0) {
                const statsRef = db.collection('system_stats').doc('economy');
                transaction.set(statsRef, {
                    accumulated_rake: admin.firestore.FieldValue.increment(platformProfit),
                    lastUpdated: timestamp
                }, { merge: true });
                console.log(`[SETTLE_ROUND] Paso 2 - Platform wallet actualizada: +${platformProfit}`);
            }

            if (clubProfit > 0 && targetClubId) {
                const clubRef = db.collection('clubs').doc(targetClubId);
                const clubDoc = await transaction.get(clubRef);
                if (clubDoc.exists) {
                    transaction.update(clubRef, {
                        walletBalance: admin.firestore.FieldValue.increment(clubProfit)
                    });
                    console.log(`[SETTLE_ROUND] Paso 2 - Club ${targetClubId} wallet actualizada: +${clubProfit}`);
                } else {
                    // Si el club no existe, el rake va a la plataforma
                    platformProfit += clubProfit;
                    const statsRef = db.collection('system_stats').doc('economy');
                    transaction.set(statsRef, {
                        accumulated_rake: admin.firestore.FieldValue.increment(clubProfit),
                        lastUpdated: timestamp
                    }, { merge: true });
                    clubProfit = 0;
                    console.log(`[SETTLE_ROUND] Paso 2 - Club no encontrado, rake transferido a plataforma`);
                }
            }

            if (sellerProfit > 0 && targetSellerId) {
                const sellerRef = db.collection('users').doc(targetSellerId);
                const sellerDoc = await transaction.get(sellerRef);
                if (sellerDoc.exists) {
                    transaction.update(sellerRef, {
                        credit: admin.firestore.FieldValue.increment(sellerProfit)
                    });
                    console.log(`[SETTLE_ROUND] Paso 2 - Seller ${targetSellerId} wallet actualizada: +${sellerProfit}`);
                } else {
                    // Si el seller no existe, el rake va al club o plataforma
                    if (targetClubId) {
                        const clubRef = db.collection('clubs').doc(targetClubId);
                        const clubDoc = await transaction.get(clubRef);
                        if (clubDoc.exists) {
                            transaction.update(clubRef, {
                                walletBalance: admin.firestore.FieldValue.increment(sellerProfit)
                            });
                            clubProfit += sellerProfit;
                            console.log(`[SETTLE_ROUND] Paso 2 - Seller no encontrado, rake transferido a club`);
                        } else {
                            platformProfit += sellerProfit;
                            const statsRef = db.collection('system_stats').doc('economy');
                            transaction.set(statsRef, {
                                accumulated_rake: admin.firestore.FieldValue.increment(sellerProfit),
                                lastUpdated: timestamp
                            }, { merge: true });
                            console.log(`[SETTLE_ROUND] Paso 2 - Seller y Club no encontrados, rake transferido a plataforma`);
                        }
                    } else {
                        platformProfit += sellerProfit;
                        const statsRef = db.collection('system_stats').doc('economy');
                        transaction.set(statsRef, {
                            accumulated_rake: admin.firestore.FieldValue.increment(sellerProfit),
                            lastUpdated: timestamp
                        }, { merge: true });
                        console.log(`[SETTLE_ROUND] Paso 2 - Seller no encontrado, rake transferido a plataforma`);
                    }
                    sellerProfit = 0;
                }
            }

            // Actualizar dailyGGR y totalVolume en stats_daily
            const now = new Date();
            const dateKey = now.toISOString().split('T')[0];
            const dailyStatsRef = db.collection('stats_daily').doc(dateKey);
            transaction.set(dailyStatsRef, {
                dateKey: dateKey,
                date: admin.firestore.Timestamp.now(),
                totalVolume: admin.firestore.FieldValue.increment(totalPot),
                dailyGGR: admin.firestore.FieldValue.increment(rakeAmount),
                totalRake: admin.firestore.FieldValue.increment(rakeAmount),
                handsPlayed: admin.firestore.FieldValue.increment(1),
                lastUpdated: admin.firestore.FieldValue.serverTimestamp()
            }, { merge: true });
            console.log(`[SETTLE_ROUND] Paso 2 - stats_daily actualizado: totalVolume +${totalPot}, dailyGGR +${rakeAmount}, totalRake +${rakeAmount}, handsPlayed +1`);

            // ============================================
            // PASO 3: ASIGNACIÓN AL GANADOR (ACTUALIZAR STACK)
            // ============================================
            // CRÍTICO: El potTotal ya incluye todas las apuestas del pot.
            // El ganador debe recibir: sus chips actuales + el pot total - el rake
            // Pero como el pot ya incluye sus apuestas, solo necesitamos sumar el premio neto
            const newWinnerChips = currentWinnerChips + winnerPrize;
            players[winnerPlayerIndex] = {
                ...winnerPlayer,
                chips: newWinnerChips
            };

            // Actualizar la mesa con las nuevas fichas del ganador
            transaction.update(tableRef, {
                [`players.${winnerPlayerIndex}.chips`]: newWinnerChips
            });

            console.log(`[SETTLE_ROUND] Paso 3 - Stack Final del Ganador: ${newWinnerChips} (chips actuales: ${currentWinnerChips}, premio neto sumado: ${winnerPrize})`);

            // ============================================
            // PASO 4: CASHOUT / LIQUIDACIÓN (TRANSFERIR A BILLETERA)
            // ============================================
            // CRÍTICO: El ganador debe recibir TODO su stack final (chips actuales + premio neto)
            // porque el buy-in ya fue descontado cuando entró a la mesa.
            // 
            // Ejemplo:
            // - Buy-in: 1000 (ya descontado del crédito al entrar)
            // - Chips actuales: 500 (después de apostar)
            // - Pot ganado: 2000, Rake: 160, Premio neto: 1840
            // - Stack final: 500 + 1840 = 2340
            // - Debe recibir: 2340 en crédito (para compensar el buy-in ya descontado)
            const creditToAdd = newWinnerChips; // Stack completo (chips actuales + premio neto)

            transaction.update(winnerRef, {
                credit: admin.firestore.FieldValue.increment(creditToAdd),
                moneyInPlay: 0
            });

            // Resetear chips del ganador en la mesa a 0 (ya transferimos todo)
            transaction.update(tableRef, {
                [`players.${winnerPlayerIndex}.chips`]: 0
            });

            // Actualizar sesión de poker del ganador con el rake pagado
            if (winnerSessionRef) {
                transaction.update(winnerSessionRef, {
                    currentChips: newWinnerChips, // Actualizar chips actuales
                    totalRakePaid: admin.firestore.FieldValue.increment(rakeAmount) // Acumular rake pagado
                });
                console.log(`[SETTLE_ROUND] Sesión de poker actualizada: currentChips=${newWinnerChips}, totalRakePaid+=${rakeAmount}`);
            }

            console.log(`[SETTLE_ROUND] Paso 4 - Cashout: ${creditToAdd} (stack completo) transferido a billetera. Chips actuales: ${currentWinnerChips}, Premio neto: ${winnerPrize}, Total: ${newWinnerChips}`);

            // ============================================
            // PASO 5: HISTORIAL (LEDGER)
            // ============================================
            const ledgerRef = db.collection('financial_ledger').doc();
            transaction.set(ledgerRef, {
                type: 'GAME_WIN',
                userId: winnerUid,
                userName: winnerData?.displayName || 'Unknown',
                tableId: tableId,
                gameId: gameId,
                amount: winnerPrize, // Lo que ganó neto en la mano (después del rake)
                totalCashedOut: creditToAdd, // Stack completo transferido a billetera
                currentChips: currentWinnerChips, // Chips que tenía antes de ganar
                potTotal: totalPot,
                rakeAmount: rakeAmount,
                platformProfit: platformProfit,
                clubProfit: clubProfit,
                sellerProfit: sellerProfit,
                timestamp: timestamp,
                description: `Ganador de ronda - Pot: ${totalPot}, Premio Neto: ${winnerPrize}, Rake: ${rakeAmount}, Stack Final: ${newWinnerChips}, Credit Añadido: ${creditToAdd}`
            });

            console.log(`[SETTLE_ROUND] Paso 5 - Ledger creado: GAME_WIN, Premio Neto: ${winnerPrize}, Stack Final: ${newWinnerChips}, Credit Añadido: ${creditToAdd}`);
        });

        // NOTA: stats_daily ya se actualiza dentro de la transacción (Paso 2)
        // No es necesario llamar a updateDailyStats() aquí para evitar duplicados

        console.log(`[SETTLE_ROUND] ✅ Liquidación completada exitosamente para mesa ${tableId}, ganador ${winnerUid}`);

        return { 
            success: true, 
            message: 'Game round settled successfully.', 
            gameId,
            tableId,
            potTotal,
            rakeAmount,
            winnerPrize
        };

    } catch (error: any) {
        console.error('[SETTLE_ROUND] ❌ Error en transacción:', error);
        throw new functions.https.HttpsError('internal', `Transaction failed: ${error.message || 'Unknown error'}`);
    }
};
