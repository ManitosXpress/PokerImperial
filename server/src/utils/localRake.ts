import * as admin from 'firebase-admin';

/**
 * LOCAL RAKE & POT DISTRIBUTION UTILITY
 * 
 * Este módulo centraliza la lógica de distribución de rake Y premios,
 * ejecutándola directamente en el servidor usando Admin SDK en lugar de
 * llamadas HTTP a Cloud Functions (que pueden fallar con errores de red/401).
 * 
 * CRÍTICO: Esta lógica ejecuta transacciones atómicas en Firestore para
 * garantizar la integridad de datos financieros.
 * 
 * 🔒 IDEMPOTENCY: Usa `hands/{handId}` con status 'DISTRIBUTED' para evitar
 *    doble procesamiento si la función se ejecuta múltiples veces.
 * 
 * FLUJO:
 * 1. Verificar idempotencia (hands/{handId} ya procesado?)
 * 2. Calcular y transferir rake a Treasury/Club/Seller
 * 3. Actualizar chips del ganador en poker_tables/{tableId}/players[]
 * 4. Marcar mano como DISTRIBUTED
 */

// 🏦 BILLETERA DE TESORERÍA (VERSATECH)
const TREASURY_ADMIN_UID = "g2ISanL5eJVfkNijF8l8jFiA5v52";

interface RakeData {
    tableId: string;
    handId: string;
    rakeTotal: number;
    isPrivate: boolean;
    potTotal: number;
    winnerUid?: string | null;
    winnerSeatIndex?: number; // Optional: direct seat index for faster lookup
    clubId?: string;
    sellerId?: string;
    // For split pots (multiple winners)
    winners?: Array<{
        uid: string;
        seatIndex: number;
        amount: number; // Net amount after rake split
    }>;
}

/**
 * Procesa y distribuye el rake + premio localmente usando Firestore transactions.
 * 
 * 🔒 IDEMPOTENCIA: Usa `hands/{handId}` con status 'DISTRIBUTED' y 
 *    `financial_ledger/pot_{tableId}_{handId}` para evitar doble cobro.
 * 
 * REGLAS DE NEGOCIO:
 * - Mesa Privada (isPrivate=true): 100% va a la plataforma
 * - Mesa Pública (isPrivate=false): 50% plataforma / 30% club / 20% seller
 *   (si falta club o seller, su parte va a la plataforma)
 * 
 * @param data - Datos del rake y ganador a procesar
 * @returns true si se procesó exitosamente, false si hubo error
 */
export async function processRakeLocal(data: RakeData): Promise<boolean> {
    // Nada que cobrar si rake es 0 o negativo
    if (data.rakeTotal <= 0 && data.potTotal <= 0) {
        console.log(`[RAKE_LOCAL] ⚠️ Rake = ${data.rakeTotal}, Pot = ${data.potTotal}. Nada que procesar.`);
        return true;
    }

    // Verificar que Firebase Admin esté inicializado
    if (!admin.apps.length) {
        console.error('[RAKE_LOCAL] ❌ Firebase Admin not initialized');
        return false;
    }

    const db = admin.firestore();
    const handRef = db.collection('hands').doc(data.handId);
    const tableRef = db.collection('poker_tables').doc(data.tableId);
    const treasuryRef = db.collection('users').doc(TREASURY_ADMIN_UID);
    const ledgerId = `pot_${data.tableId}_${data.handId}`;
    const ledgerRef = db.collection('financial_ledger').doc(ledgerId);

    console.log(`[RAKE_LOCAL] 🎯 Procesando: handId=${data.handId}, tableId=${data.tableId}`);
    console.log(`[RAKE_LOCAL] 📊 Pot: ${data.potTotal} | Rake: ${data.rakeTotal} | Winner: ${data.winnerUid}`);

    try {
        await db.runTransaction(async (transaction) => {
            // ═══════════════════════════════════════════════════════════════
            // 1. 🔒 IDEMPOTENCIA: Verificar si ya se procesó esta mano
            // ═══════════════════════════════════════════════════════════════
            const handDoc = await transaction.get(handRef);
            if (handDoc.exists && handDoc.data()?.status === 'DISTRIBUTED') {
                console.log(`[RAKE_LOCAL] ⚠️ Hand ${data.handId} ya DISTRIBUTED. Saltando (idempotencia).`);
                return; // No hacer nada, ya existe
            }

            // Verificar también el ledger por seguridad extra
            const ledgerDoc = await transaction.get(ledgerRef);
            if (ledgerDoc.exists) {
                console.log(`[RAKE_LOCAL] ⚠️ Ledger entry ${ledgerId} ya existe. Saltando (idempotencia).`);
                return;
            }

            // ═══════════════════════════════════════════════════════════════
            // 2. Leer la mesa para encontrar el índice del ganador
            // ═══════════════════════════════════════════════════════════════
            const tableDoc = await transaction.get(tableRef);
            const tableData = tableDoc.exists ? tableDoc.data() : null;
            const players: any[] = Array.isArray(tableData?.players) ? [...tableData.players] : [];

            // Calcular netPot (lo que recibe el ganador)
            const netPot = data.potTotal - data.rakeTotal;

            // ═══════════════════════════════════════════════════════════════
            // 3. CALCULAR COMISIONES (REGLAS DE NEGOCIO)
            // ═══════════════════════════════════════════════════════════════
            let platformShare = 0;
            let clubShare = 0;
            let sellerShare = 0;

            if (data.rakeTotal > 0) {
                if (data.isPrivate) {
                    // MESA PRIVADA: 100% va a la plataforma
                    platformShare = data.rakeTotal;
                    console.log(`[RAKE_LOCAL] 🔒 Mesa privada: 100% (${platformShare}) a plataforma.`);
                } else {
                    // MESA PÚBLICA: Distribución 50/30/20 (platform/club/seller)
                    platformShare = Math.floor(data.rakeTotal * 0.50);

                    if (data.clubId) {
                        clubShare = Math.floor(data.rakeTotal * 0.30);
                    } else {
                        platformShare += Math.floor(data.rakeTotal * 0.30);
                    }

                    if (data.sellerId) {
                        sellerShare = Math.floor(data.rakeTotal * 0.20);
                    } else {
                        platformShare += Math.floor(data.rakeTotal * 0.20);
                    }

                    // Ajustar por redondeo (centavos perdidos van a la plataforma)
                    const allocated = platformShare + clubShare + sellerShare;
                    if (allocated < data.rakeTotal) {
                        platformShare += (data.rakeTotal - allocated);
                    }

                    console.log(`[RAKE_LOCAL] 🌐 Mesa pública: Platform=${platformShare}, Club=${clubShare}, Seller=${sellerShare}`);
                }
            }

            // ═══════════════════════════════════════════════════════════════
            // 4. 💸 LECTURA DE DOCUMENTOS PARA TRANSFERENCIAS
            //    CRÍTICO: En Firestore transactions, TODOS los reads deben
            //    hacerse ANTES de cualquier write
            // ═══════════════════════════════════════════════════════════════

            // Siempre leer treasury (lo necesitaremos para fallbacks también)
            const treasuryDoc = await transaction.get(treasuryRef);
            if (!treasuryDoc.exists) {
                console.error(`[RAKE_LOCAL] ❌ CRITICAL: Treasury user ${TREASURY_ADMIN_UID} not found!`);
                throw new Error(`Treasury user ${TREASURY_ADMIN_UID} not found`);
            }

            // Leer club si es necesario
            let clubDocRead: FirebaseFirestore.DocumentSnapshot | null = null;
            const clubRefLocal = data.clubId ? db.collection('clubs').doc(data.clubId) : null;
            if (clubShare > 0 && clubRefLocal) {
                clubDocRead = await transaction.get(clubRefLocal);
            }

            // Leer seller si es necesario
            let sellerDocRead: FirebaseFirestore.DocumentSnapshot | null = null;
            const sellerRefLocal = data.sellerId ? db.collection('users').doc(data.sellerId) : null;
            if (sellerShare > 0 && sellerRefLocal) {
                sellerDocRead = await transaction.get(sellerRefLocal);
            }

            // ═══════════════════════════════════════════════════════════════
            // 5. 💸 ESCRITURA DE TRANSFERENCIAS DEL RAKE
            // ═══════════════════════════════════════════════════════════════

            // A. Platform (Treasury)
            if (platformShare > 0) {
                transaction.update(treasuryRef, {
                    credit: admin.firestore.FieldValue.increment(platformShare),
                    totalRakeReceived: admin.firestore.FieldValue.increment(platformShare),
                    lastRakeReceived: admin.firestore.FieldValue.serverTimestamp()
                });
                console.log(`[RAKE_LOCAL] 💵 Treasury recibe: ${platformShare}`);

                // 📝 CREAR TRANSACTION LOG PARA LA BILLETERA DEL ADMIN
                //    CRITICAL: Esto hace que el rake aparezca en "Mi Billetera" del admin
                const adminTxLogRef = db.collection('transaction_logs').doc();
                transaction.set(adminTxLogRef, {
                    userId: TREASURY_ADMIN_UID,
                    amount: platformShare,
                    type: 'credit',
                    reason: `Rake - ${data.isPrivate ? 'Private' : 'Public'} Table`,
                    timestamp: admin.firestore.FieldValue.serverTimestamp(),
                    metadata: {
                        handId: data.handId,
                        tableId: data.tableId,
                        potTotal: data.potTotal,
                        rakeTotal: data.rakeTotal,
                        platformShare: platformShare,
                        isPrivate: !!data.isPrivate
                    }
                });
            }

            // B. Club
            if (clubShare > 0 && clubRefLocal && clubDocRead) {
                if (clubDocRead.exists) {
                    transaction.update(clubRefLocal, {
                        walletBalance: admin.firestore.FieldValue.increment(clubShare),
                        totalRakeEarned: admin.firestore.FieldValue.increment(clubShare),
                        lastRakeReceived: admin.firestore.FieldValue.serverTimestamp()
                    });
                    console.log(`[RAKE_LOCAL] 🏠 Club ${data.clubId} recibe: ${clubShare}`);
                } else {
                    // Si el club no existe, el dinero va a la plataforma
                    transaction.update(treasuryRef, {
                        credit: admin.firestore.FieldValue.increment(clubShare)
                    });
                    console.warn(`[RAKE_LOCAL] ⚠️ Club ${data.clubId} no existe. ${clubShare} redirigido a plataforma.`);
                }
            }

            // C. Seller
            if (sellerShare > 0 && sellerRefLocal && sellerDocRead) {
                if (sellerDocRead.exists) {
                    transaction.update(sellerRefLocal, {
                        credit: admin.firestore.FieldValue.increment(sellerShare),
                        commissionEarned: admin.firestore.FieldValue.increment(sellerShare),
                        lastCommissionReceived: admin.firestore.FieldValue.serverTimestamp()
                    });
                    console.log(`[RAKE_LOCAL] 👤 Seller ${data.sellerId} recibe: ${sellerShare}`);
                } else {
                    // Si el seller no existe, el dinero va a la plataforma
                    transaction.update(treasuryRef, {
                        credit: admin.firestore.FieldValue.increment(sellerShare)
                    });
                    console.warn(`[RAKE_LOCAL] ⚠️ Seller ${data.sellerId} no existe. ${sellerShare} redirigido a plataforma.`);
                }
            }

            // ═══════════════════════════════════════════════════════════════
            // 6. 🏆 ACTUALIZAR CHIPS DEL GANADOR EN LA MESA
            //    CRÍTICO: Firestore NO permite actualizar elementos de array
            //    por índice con dot notation. Debemos actualizar el array completo.
            // ═══════════════════════════════════════════════════════════════
            let playersModified = false;

            if (tableDoc.exists && players.length > 0) {
                if (data.winners && data.winners.length > 0) {
                    // SPLIT POT: Múltiples ganadores
                    for (const winner of data.winners) {
                        let winnerIndex = winner.seatIndex;

                        if (winnerIndex === undefined || winnerIndex === null || winnerIndex < 0) {
                            winnerIndex = players.findIndex((p: any) =>
                                p && (p.uid === winner.uid || p.id === winner.uid)
                            );
                        }

                        if (winnerIndex !== -1 && winnerIndex < players.length && players[winnerIndex]) {
                            const currentChips = players[winnerIndex].chips || 0;
                            players[winnerIndex].chips = currentChips + winner.amount;
                            playersModified = true;
                            console.log(`[RAKE_LOCAL] 🏆 Winner ${winner.uid} (seat ${winnerIndex}): +${winner.amount} chips (now: ${players[winnerIndex].chips})`);
                        } else {
                            console.warn(`[RAKE_LOCAL] ⚠️ Winner ${winner.uid} no encontrado en mesa (index: ${winnerIndex}). Saltando.`);
                        }
                    }
                } else if (data.winnerUid && netPot > 0) {
                    // GANADOR ÚNICO
                    let winnerIndex = data.winnerSeatIndex;

                    if (winnerIndex === undefined || winnerIndex === null || winnerIndex < 0) {
                        winnerIndex = players.findIndex((p: any) =>
                            p && (p.uid === data.winnerUid || p.id === data.winnerUid)
                        );
                    }

                    if (winnerIndex !== -1 && winnerIndex < players.length && players[winnerIndex]) {
                        const currentChips = players[winnerIndex].chips || 0;
                        players[winnerIndex].chips = currentChips + netPot;
                        playersModified = true;
                        console.log(`[RAKE_LOCAL] 🏆 Winner ${data.winnerUid} (seat ${winnerIndex}): +${netPot} chips (now: ${players[winnerIndex].chips})`);
                    } else {
                        console.warn(`[RAKE_LOCAL] ⚠️ Winner ${data.winnerUid} no encontrado (index: ${winnerIndex}). Saltando actualización de chips.`);
                    }
                }

                // Escribir el array de players completo si hubo modificaciones
                if (playersModified) {
                    transaction.update(tableRef, { players: players });
                }
            }

            // [FIX] Obtener nombre del ganador para el ledger
            let winnerName = 'Unknown';
            if (data.winnerUid) {
                const winnerPlayer = players.find((p: any) => p && (p.uid === data.winnerUid || p.id === data.winnerUid));
                if (winnerPlayer) {
                    winnerName = winnerPlayer.name || winnerPlayer.displayName || 'Unknown';
                }
            }

            // ═══════════════════════════════════════════════════════════════
            // 7. 📝 CREAR ENTRADA EN LEDGER (Auditoría)
            // ═══════════════════════════════════════════════════════════════
            transaction.set(ledgerRef, {
                type: 'POT_DISTRIBUTED',
                handId: data.handId,
                tableId: data.tableId,
                potTotal: data.potTotal,
                rakeAmount: data.rakeTotal,
                netPotDistributed: netPot,
                winnerUid: data.winnerUid || null,
                winnerName: winnerName, // [FIX] Nombre del ganador para UI
                userName: winnerName,   // [FIX] Para compatibilidad con historial
                winners: data.winners || null,
                isPrivate: !!data.isPrivate,
                rakeBreakdown: {
                    platform: platformShare,
                    club: clubShare,
                    seller: sellerShare
                },
                clubId: data.clubId || null,
                sellerId: data.sellerId || null,
                treasuryUid: TREASURY_ADMIN_UID,
                processedAt: admin.firestore.FieldValue.serverTimestamp(),
                method: 'LOCAL_EXECUTION'
            });

            // ═══════════════════════════════════════════════════════════════
            // 7b. 📝 CREAR ENTRADA DE RAKE EN LEDGER (Para Finance History)
            //     CRITICAL: Esta entrada separada permite que el Admin Panel
            //     muestre las transacciones de Rake en el historial financiero
            // ═══════════════════════════════════════════════════════════════
            if (data.rakeTotal > 0) {
                const rakeLedgerId = `rake_${data.tableId}_${data.handId}`;
                const rakeLedgerRef = db.collection('financial_ledger').doc(rakeLedgerId);

                transaction.set(rakeLedgerRef, {
                    type: 'RAKE',
                    amount: data.rakeTotal,
                    source: `table_${data.tableId}`,
                    destination: 'SYSTEM',
                    description: `Rake collected from hand ${data.handId}`,
                    timestamp: admin.firestore.FieldValue.serverTimestamp(),
                    metadata: {
                        handId: data.handId,
                        tableId: data.tableId,
                        potTotal: data.potTotal,
                        breakdown: {
                            platform: platformShare,
                            club: clubShare,
                            seller: sellerShare
                        },
                        isPrivate: !!data.isPrivate,
                        clubId: data.clubId || null,
                        sellerId: data.sellerId || null,
                        treasuryUid: TREASURY_ADMIN_UID
                    }
                });
                console.log(`[RAKE_LOCAL] 📊 Rake ledger entry created: ${rakeLedgerId}`);
            }

            // ═══════════════════════════════════════════════════════════════
            // 8. 🔒 MARCAR MANO COMO DISTRIBUTED (Lock de Idempotencia)
            // ═══════════════════════════════════════════════════════════════
            transaction.set(handRef, {
                status: 'DISTRIBUTED',
                tableId: data.tableId,
                potTotal: data.potTotal,
                rakeCollected: data.rakeTotal,
                netPotDistributed: netPot,
                winnerUid: data.winnerUid || null,
                distributedAt: admin.firestore.FieldValue.serverTimestamp()
            }, { merge: true });

            // ═══════════════════════════════════════════════════════════════
            // 9. 📊 ACTUALIZAR STATS DEL SISTEMA
            // ═══════════════════════════════════════════════════════════════
            if (data.rakeTotal > 0) {
                transaction.set(db.collection('system_stats').doc('economy'), {
                    accumulated_rake: admin.firestore.FieldValue.increment(data.rakeTotal),
                    total_volume: admin.firestore.FieldValue.increment(data.potTotal),
                    hands_played: admin.firestore.FieldValue.increment(1),
                    lastUpdated: admin.firestore.FieldValue.serverTimestamp()
                }, { merge: true });

                const dateKey = new Date().toISOString().split('T')[0];
                transaction.set(db.collection('stats_daily').doc(dateKey), {
                    dateKey,
                    totalVolume: admin.firestore.FieldValue.increment(data.potTotal),
                    totalRake: admin.firestore.FieldValue.increment(data.rakeTotal),
                    handsPlayed: admin.firestore.FieldValue.increment(1),
                    lastUpdated: admin.firestore.FieldValue.serverTimestamp()
                }, { merge: true });
            }
        });

        console.log(`[RAKE_LOCAL] ✅ Éxito: Hand ${data.handId} procesada. Rake: ${data.rakeTotal}, NetPot: ${data.potTotal - data.rakeTotal}`);
        return true;
    } catch (error: any) {
        console.error(`[RAKE_LOCAL] ❌ Error crítico procesando rake:`, error);
        console.error(`[RAKE_LOCAL] ❌ Mensaje: ${error.message}`);
        console.error(`[RAKE_LOCAL] ❌ Stack: ${error.stack}`);
        return false;
    }
}

/**
 * Obtiene el UID del treasury admin para referencia externa
 */
export function getTreasuryUid(): string {
    return TREASURY_ADMIN_UID;
}
