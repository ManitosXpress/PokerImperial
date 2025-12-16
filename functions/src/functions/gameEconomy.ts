import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { SettleRoundRequest } from "../types";

// Lazy initialization de Firestore para evitar timeout en deploy
const getDb = () => {
    if (!admin.apps.length) {
        admin.initializeApp();
    }
    return admin.firestore();
};

/**
 * settleGameRound - Motor de Distribución del Rake
 * 
 * REGLA INQUEBRANTABLE #3: DISTRIBUCIÓN DEL RAKE
 * Durante el juego, el rake se calcula y distribuye, pero el dinero del usuario
 * NO se transfiere a su billetera. Las fichas quedan en la mesa hasta el cashout final.
 * 
 * Matemática: GrossProfit = FichasFinales - BuyIn
 * Regla de Distribución (Si hay ganancia):
 * - Privada: 100% Rake a Plataforma
 * - Pública: 50% Plataforma / 30% Club Owner / 20% Seller
 * 
 * Persistencia: El Rake DEBE escribirse en system_stats (campo accumulated_rake) 
 * y en las billeteras de Club/Seller si corresponde.
 * 
 * ALGORITMO ESTRICTO Y SECUENCIAL PARA LIQUIDACIÓN DE RONDAS:
 * 
 * Paso 1: Cálculo del Bote y Rake (EN MEMORIA)
 * Paso 2: Distribución del Rake según tipo de mesa (ESCRIBIR EN BD)
 * Paso 3: Actualizar Stack del Ganador en la Mesa (ÚNICA FUENTE DE VERDAD)
 * Paso 4: Actualizar Sesión (solo auditoría)
 * Paso 5: Historial (Ledger)
 * Paso 6: Actualizar Estadísticas Diarias
 * 
 * CRÍTICO: 
 * - NO se transfiere crédito a la billetera del usuario
 * - NO se limpia moneyInPlay ni currentTableId
 * - NO se resetean las fichas a 0 en la mesa
 * - Las fichas en poker_tables son la ÚNICA fuente de verdad
 * - El dinero se transferirá solo cuando el usuario haga processCashOut
 */
export const settleGameRound = async (data: SettleRoundRequest, context: functions.https.CallableContext) => {
    const db = getDb();

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
            // REGLA INQUEBRANTABLE: Distribución según tipo de mesa
            // ============================================
            let platformProfit = 0;
            let clubProfit = 0;
            let sellerProfit = 0;
            let targetClubId: string | null = null;
            let targetSellerId: string | null = null;

            if (!isPublic) {
                // Mesa Privada: 100% del rake va a la plataforma
                platformProfit = rakeAmount;
                console.log(`[SETTLE_ROUND] Paso 2 - Mesa Privada: Rake 100% a Plataforma = ${platformProfit}`);
            } else {
                // Mesa Pública: Distribución 50-30-20
                platformProfit = Math.floor(rakeAmount * 0.50);
                clubProfit = Math.floor(rakeAmount * 0.30);
                sellerProfit = Math.floor(rakeAmount * 0.20);
                
                // Ajustar por redondeo (el resto va a la plataforma)
                const remainder = rakeAmount - (platformProfit + clubProfit + sellerProfit);
                platformProfit += remainder;

                targetClubId = winnerClubId || null;
                targetSellerId = winnerSellerId || null;

                // Si no hay seller, el 20% va al club
                if (!targetSellerId && targetClubId) {
                    clubProfit += sellerProfit;
                    sellerProfit = 0;
                    console.log(`[SETTLE_ROUND] Paso 2 - Sin Seller: 20% transferido a Club`);
                } else if (!targetSellerId && !targetClubId) {
                    // Si no hay club ni seller, todo va a la plataforma
                    platformProfit += clubProfit + sellerProfit;
                    clubProfit = 0;
                    sellerProfit = 0;
                    console.log(`[SETTLE_ROUND] Paso 2 - Sin Club ni Seller: Todo a Plataforma`);
                }

                console.log(`[SETTLE_ROUND] Paso 2 - Mesa Pública: Platform=${platformProfit}, Club=${clubProfit}, Seller=${sellerProfit}`);
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
            // PASO 4: ACTUALIZAR SESIÓN (SOLO AUDITORÍA)
            // ============================================
            // CRÍTICO: Durante el juego, NO se transfiere dinero a la billetera.
            // Las fichas quedan en la mesa y solo se actualiza la sesión para auditoría.
            // El dinero se transferirá solo cuando el usuario haga processCashOut.
            if (winnerSessionRef) {
                transaction.update(winnerSessionRef, {
                    currentChips: newWinnerChips, // Actualizar chips actuales (solo auditoría, NO fuente de verdad)
                    totalRakePaid: admin.firestore.FieldValue.increment(rakeAmount) // Acumular rake pagado
                });
                console.log(`[SETTLE_ROUND] Paso 4 - Sesión actualizada (auditoría): currentChips=${newWinnerChips}, totalRakePaid+=${rakeAmount}`);
            }

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
                currentChips: currentWinnerChips, // Chips que tenía antes de ganar
                finalChips: newWinnerChips, // Chips finales después de ganar
                potTotal: totalPot,
                rakeAmount: rakeAmount,
                platformProfit: platformProfit,
                clubProfit: clubProfit,
                sellerProfit: sellerProfit,
                timestamp: timestamp,
                description: `Ganador de ronda - Pot: ${totalPot}, Premio Neto: ${winnerPrize}, Rake: ${rakeAmount}, Stack Final: ${newWinnerChips} (fichas quedan en mesa, no se transfiere a billetera)`
            });

            console.log(`[SETTLE_ROUND] Paso 5 - Ledger creado: GAME_WIN, Premio Neto: ${winnerPrize}, Stack Final: ${newWinnerChips} (fichas en mesa)`);
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
