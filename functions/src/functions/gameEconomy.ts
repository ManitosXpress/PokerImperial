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
 * ═══════════════════════════════════════════════════════════════════════════
 * SETTLE GAME ROUND - REESCRITURA COMPLETA CON FIRESTORE TRANSACTIONS
 * ═══════════════════════════════════════════════════════════════════════════
 * 
 * REGLA DE ORO #1: LAS FICHAS QUEDAN EN LA MESA
 * - Durante el juego, el rake se cobra pero las fichas NO van a la billetera del usuario
 * - Las fichas del ganador se actualizan en poker_tables/{tableId}/players/{uid}/chips
 * - El usuario NO toca su wallet.credit hasta hacer processCashOut
 * 
 * REGLA DE ORO #2: DISTRIBUCIÓN DE RAKE SIN INTERMEDIARIOS
 * - El rake se deposita DIRECTAMENTE en las billeteras de platform/club/seller
 * - system_stats.dailyGGR se actualiza inmediatamente
 * - clubs/{clubId}.walletBalance se actualiza inmediatamente
 * - users/{sellerId}.credit se actualiza inmediatamente
 * 
 * ALGORITMO DEFINITIVO:
 * 
 * Paso 1: Calcular Rake = potTotal * 0.08
 * Paso 2: Calcular Premio Neto = potTotal - Rake
 * Paso 3: Actualizar poker_tables: ganador.chips += Premio Neto
 * Paso 4: Distribuir Rake según tipo de mesa:
 *   - Privada: 100% → system_stats
 *   - Pública: 50% → system_stats, 30% → club, 20% → seller
 * Paso 5: Ledger tipo RAKE_COLLECTED (asociado a mesa, NO a usuario)
 * Paso 6: Actualizar stats_daily (GGR + volume)
 * 
 * CRÍTICO: NO tocar users/{uid}/credit
 * CRÍTICO: NO tocar users/{uid}/moneyInPlay
 * CRÍTICO: NO tocar users/{uid}/currentTableId
 * 
 * @param data - { potTotal, winnerUid, playersInvolved, gameId, tableId }
 * @param context - Contexto de autenticación
 * @returns Resumen de la liquidación
 */
export const settleGameRound = async (data: SettleRoundRequest, context: functions.https.CallableContext) => {
    // ════════════════════════════════════════════════════════════════════════
    // PASO 1: VALIDACIONES BÁSICAS
    // ════════════════════════════════════════════════════════════════════════
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
    }

    const db = getDb();
    const { potTotal, winnerUid, playersInvolved, gameId, tableId } = data;

    if (!potTotal || !winnerUid || !playersInvolved || playersInvolved.length === 0 || !tableId) {
        throw new functions.https.HttpsError('invalid-argument', 'Missing required parameters: potTotal, winnerUid, playersInvolved, tableId.');
    }

    console.log(`[SETTLE_ROUND] 🎯 Iniciando liquidación de ronda en mesa ${tableId}, ganador: ${winnerUid}, pot: ${potTotal}`);

    // ════════════════════════════════════════════════════════════════════════
    // PASO 2: CÁLCULO DEL RAKE Y PREMIO
    // ════════════════════════════════════════════════════════════════════════
    const RAKE_PERCENTAGE = 0.08;
    const rakeAmount = Math.floor(potTotal * RAKE_PERCENTAGE);
    const winnerPrize = potTotal - rakeAmount;

    console.log(`[SETTLE_ROUND] 💰 Cálculo: Pot=${potTotal}, Rake=${rakeAmount} (8%), Premio Neto=${winnerPrize}`);

    try {
        // ════════════════════════════════════════════════════════════════════════
        // PASO 3: TRANSACCIÓN ATÓMICA - DISTRIBUCIÓN DE RAKE Y ACTUALIZACIÓN DE MESA
        // ════════════════════════════════════════════════════════════════════════
        const timestamp = admin.firestore.Timestamp.now();

        await db.runTransaction(async (transaction) => {
            console.log(`[SETTLE_ROUND] 🔒 Iniciando transacción atómica`);

            // ───────────────────────────────────────────────────────────────────
            // 3.1. LEER MESA Y OBTENER CONFIGURACIÓN
            // ───────────────────────────────────────────────────────────────────
            const tableRef = db.collection('poker_tables').doc(tableId);
            const tableDoc = await transaction.get(tableRef);

            if (!tableDoc.exists) {
                throw new functions.https.HttpsError('not-found', `Table ${tableId} not found.`);
            }

            const tableData = tableDoc.data();
            const isPublic = tableData?.isPublic === true;
            const players = Array.isArray(tableData?.players) ? [...tableData.players] : [];

            // Encontrar el jugador ganador
            const winnerIndex = players.findIndex((p: any) => p.id === winnerUid);
            if (winnerIndex === -1) {
                throw new functions.https.HttpsError('not-found', `Winner ${winnerUid} not found in table players.`);
            }

            const winnerPlayer = players[winnerIndex];
            const currentWinnerChips = Number(winnerPlayer.chips) || 0;

            console.log(`[SETTLE_ROUND] 🎲 Mesa tipo: ${isPublic ? 'Pública' : 'Privada'}, Chips actuales ganador: ${currentWinnerChips}`);

            // ───────────────────────────────────────────────────────────────────
            // 3.2. LEER DATOS DEL GANADOR (para distribución de rake)
            // ───────────────────────────────────────────────────────────────────
            const winnerRef = db.collection('users').doc(winnerUid);
            const winnerDoc = await transaction.get(winnerRef);

            if (!winnerDoc.exists) {
                throw new functions.https.HttpsError('not-found', `Winner user ${winnerUid} not found.`);
            }

            const winnerData = winnerDoc.data();
            const winnerDisplayName = winnerData?.displayName || 'Unknown';
            const winnerClubId = winnerData?.clubId;
            const winnerSellerId = winnerData?.sellerId;

            // ───────────────────────────────────────────────────────────────────
            // 3.3. ACTUALIZAR CHIPS DEL GANADOR EN LA MESA (ÚNICA FUENTE DE VERDAD)
            // ───────────────────────────────────────────────────────────────────
            const newWinnerChips = currentWinnerChips + winnerPrize;

            transaction.update(tableRef, {
                [`players.${winnerIndex}.chips`]: newWinnerChips
            });

            console.log(`[SETTLE_ROUND] 🏆 Stack ganador actualizado: ${currentWinnerChips} → ${newWinnerChips} (+${winnerPrize})`);

            // ───────────────────────────────────────────────────────────────────
            // 3.4. DISTRIBUCIÓN DEL RAKE
            // ───────────────────────────────────────────────────────────────────
            let platformShare = 0;
            let clubShare = 0;
            let sellerShare = 0;

            if (!isPublic) {
                // MESA PRIVADA: 100% a la plataforma
                platformShare = rakeAmount;
                console.log(`[SETTLE_ROUND] 💼 Mesa Privada: Rake 100% → Platform (${platformShare})`);
            } else {
                // MESA PÚBLICA: Distribución 50-30-20
                platformShare = Math.floor(rakeAmount * 0.50);
                clubShare = Math.floor(rakeAmount * 0.30);
                sellerShare = Math.floor(rakeAmount * 0.20);

                // Ajustar por redondeo
                const remainder = rakeAmount - (platformShare + clubShare + sellerShare);
                platformShare += remainder;

                console.log(`[SETTLE_ROUND] 💼 Mesa Pública: Platform=${platformShare} (50%), Club=${clubShare} (30%), Seller=${sellerShare} (20%)`);
            }

            // Aplicar distribución del rake
            const rakeDistribution: any = {
                platform: platformShare,
                club: 0,
                seller: 0
            };

            // 3.4.1. Platform
            if (platformShare > 0) {
                const statsRef = db.collection('system_stats').doc('economy');
                transaction.set(statsRef, {
                    accumulated_rake: admin.firestore.FieldValue.increment(platformShare),
                    dailyGGR: admin.firestore.FieldValue.increment(platformShare),
                    lastUpdated: timestamp
                }, { merge: true });
                console.log(`[SETTLE_ROUND] ✅ Platform rake: +${platformShare}`);
            }

            // 3.4.2. Club (si es pública y existe club)
            if (clubShare > 0 && winnerClubId) {
                const clubRef = db.collection('clubs').doc(winnerClubId);
                const clubDoc = await transaction.get(clubRef);

                if (clubDoc.exists) {
                    transaction.update(clubRef, {
                        walletBalance: admin.firestore.FieldValue.increment(clubShare)
                    });
                    rakeDistribution.club = clubShare;
                    console.log(`[SETTLE_ROUND] ✅ Club rake: +${clubShare} → ${winnerClubId}`);
                } else {
                    // Club no existe, transferir a plataforma
                    platformShare += clubShare;
                    const statsRef = db.collection('system_stats').doc('economy');
                    transaction.set(statsRef, {
                        accumulated_rake: admin.firestore.FieldValue.increment(clubShare)
                    }, { merge: true });
                    console.log(`[SETTLE_ROUND] ⚠️ Club no existe, rake transferido a platform`);
                }
            } else if (clubShare > 0) {
                // No hay club, transferir a plataforma
                platformShare += clubShare;
                const statsRef = db.collection('system_stats').doc('economy');
                transaction.set(statsRef, {
                    accumulated_rake: admin.firestore.FieldValue.increment(clubShare)
                }, { merge: true });
            }

            // 3.4.3. Seller (si es pública y existe seller)
            if (sellerShare > 0 && winnerSellerId) {
                const sellerRef = db.collection('users').doc(winnerSellerId);
                const sellerDoc = await transaction.get(sellerRef);

                if (sellerDoc.exists) {
                    transaction.update(sellerRef, {
                        credit: admin.firestore.FieldValue.increment(sellerShare)
                    });
                    rakeDistribution.seller = sellerShare;
                    console.log(`[SETTLE_ROUND] ✅ Seller rake: +${sellerShare} → ${winnerSellerId}`);
                } else {
                    // Seller no existe, transferir a club o plataforma
                    if (winnerClubId) {
                        const clubRef = db.collection('clubs').doc(winnerClubId);
                        const clubDoc = await transaction.get(clubRef);
                        if (clubDoc.exists) {
                            transaction.update(clubRef, {
                                walletBalance: admin.firestore.FieldValue.increment(sellerShare)
                            });
                            rakeDistribution.club += sellerShare;
                            console.log(`[SETTLE_ROUND] ⚠️ Seller no existe, rake transferido a club`);
                        } else {
                            platformShare += sellerShare;
                            const statsRef = db.collection('system_stats').doc('economy');
                            transaction.set(statsRef, {
                                accumulated_rake: admin.firestore.FieldValue.increment(sellerShare)
                            }, { merge: true });
                        }
                    } else {
                        platformShare += sellerShare;
                        const statsRef = db.collection('system_stats').doc('economy');
                        transaction.set(statsRef, {
                            accumulated_rake: admin.firestore.FieldValue.increment(sellerShare)
                        }, { merge: true });
                    }
                }
            } else if (sellerShare > 0) {
                // No hay seller, transferir a club o plataforma
                if (winnerClubId) {
                    const clubRef = db.collection('clubs').doc(winnerClubId);
                    const clubDoc = await transaction.get(clubRef);
                    if (clubDoc.exists) {
                        transaction.update(clubRef, {
                            walletBalance: admin.firestore.FieldValue.increment(sellerShare)
                        });
                        rakeDistribution.club += sellerShare;
                    } else {
                        platformShare += sellerShare;
                        const statsRef = db.collection('system_stats').doc('economy');
                        transaction.set(statsRef, {
                            accumulated_rake: admin.firestore.FieldValue.increment(sellerShare)
                        }, { merge: true });
                    }
                } else {
                    platformShare += sellerShare;
                    const statsRef = db.collection('system_stats').doc('economy');
                    transaction.set(statsRef, {
                        accumulated_rake: admin.firestore.FieldValue.increment(sellerShare)
                    }, { merge: true });
                }
            }

            // ───────────────────────────────────────────────────────────────────
            // 3.5. LEDGER: RAKE_COLLECTED (asociado a la mesa, NO al usuario)
            // ───────────────────────────────────────────────────────────────────
            const ledgerRef = db.collection('financial_ledger').doc();
            transaction.set(ledgerRef, {
                type: 'RAKE_COLLECTED', // IMPORTANTE: Tipo tabla-level, NO user-level
                tableId: tableId,
                handId: gameId,
                potTotal: potTotal,
                rakeAmount: rakeAmount,
                distribution: rakeDistribution,
                winnerUid: winnerUid,
                winnerName: winnerDisplayName,
                winnerPrize: winnerPrize,
                timestamp: timestamp,
                description: `Rake collected from hand ${gameId} - Pot: ${potTotal}, Rake: ${rakeAmount}, Winner: ${winnerDisplayName}`
            });

            console.log(`[SETTLE_ROUND] 📊 Ledger creado: RAKE_COLLECTED, pot=${potTotal}, rake=${rakeAmount}`);

            // ───────────────────────────────────────────────────────────────────
            // 3.6. ACTUALIZAR ESTADÍSTICAS DIARIAS
            // ───────────────────────────────────────────────────────────────────
            const now = new Date();
            const dateKey = now.toISOString().split('T')[0];
            const dailyStatsRef = db.collection('stats_daily').doc(dateKey);

            transaction.set(dailyStatsRef, {
                dateKey: dateKey,
                date: admin.firestore.Timestamp.now(),
                totalVolume: admin.firestore.FieldValue.increment(potTotal),
                dailyGGR: admin.firestore.FieldValue.increment(rakeAmount),
                totalRake: admin.firestore.FieldValue.increment(rakeAmount),
                handsPlayed: admin.firestore.FieldValue.increment(1),
                lastUpdated: admin.firestore.FieldValue.serverTimestamp()
            }, { merge: true });

            console.log(`[SETTLE_ROUND] 📈 Stats diarias actualizadas: volume +${potTotal}, GGR +${rakeAmount}, hands +1`);

            console.log(`[SETTLE_ROUND] ✅ Transacción completada exitosamente`);
        });

        console.log(`[SETTLE_ROUND] 🎉 Ronda liquidada: Ganador ${winnerUid} recibe ${winnerPrize}, Rake ${rakeAmount} distribuido`);

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

        if (error instanceof functions.https.HttpsError) {
            throw error;
        }

        throw new functions.https.HttpsError('internal', `Transaction failed: ${error.message || 'Unknown error'}`);
    }
};
