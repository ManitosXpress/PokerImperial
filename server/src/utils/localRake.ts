import * as admin from 'firebase-admin';

/**
 * LOCAL RAKE DISTRIBUTION UTILITY
 * 
 * Este módulo centraliza la lógica de distribución de rake,
 * ejecutándola directamente en el servidor usando Admin SDK en lugar de
 * llamadas HTTP a Cloud Functions (que pueden fallar con errores de red/401).
 * 
 * CRÍTICO: Esta lógica ejecuta transacciones atómicas en Firestore para
 * garantizar la integridad de datos financieros.
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
    clubId?: string;
    sellerId?: string;
}

/**
 * Procesa y distribuye el rake localmente usando Firestore transactions.
 * 
 * IDEMPOTENCIA: Usa `rake_${tableId}_${handId}` como ID único para evitar
 * doble cobro si la función se ejecuta múltiples veces.
 * 
 * REGLAS DE NEGOCIO:
 * - Mesa Privada (isPrivate=true): 100% va a la plataforma
 * - Mesa Pública (isPrivate=false): 50% plataforma (el resto se puede distribuir a club/seller)
 * 
 * @param data - Datos del rake a procesar
 * @returns true si se procesó exitosamente, false si hubo error
 */
export async function processRakeLocal(data: RakeData): Promise<boolean> {
    // Nada que cobrar si rake es 0 o negativo
    if (data.rakeTotal <= 0) {
        console.log(`[RAKE_LOCAL] ⚠️ Rake = ${data.rakeTotal}. Nada que procesar.`);
        return true;
    }

    // Verificar que Firebase Admin esté inicializado
    if (!admin.apps.length) {
        console.error('[RAKE_LOCAL] ❌ Firebase Admin not initialized');
        return false;
    }

    const db = admin.firestore();
    const ledgerId = `rake_${data.tableId}_${data.handId}`;
    const ledgerRef = db.collection('financial_ledger').doc(ledgerId);
    const treasuryRef = db.collection('users').doc(TREASURY_ADMIN_UID);

    console.log(`[RAKE_LOCAL] 🎯 Procesando rake: handId=${data.handId}, tableId=${data.tableId}, rakeTotal=${data.rakeTotal}`);

    try {
        await db.runTransaction(async (transaction) => {
            // 1. IDEMPOTENCIA: Verificar si ya se cobró esta mano
            const doc = await transaction.get(ledgerRef);
            if (doc.exists) {
                console.log(`[RAKE_LOCAL] ⚠️ Rake para mano ${data.handId} ya procesado. Saltando (idempotencia).`);
                return; // No hacer nada, ya existe
            }

            // 2. CALCULAR COMISIONES (REGLAS DE NEGOCIO)
            let platformShare = 0;
            let clubShare = 0;
            let sellerShare = 0;

            if (data.isPrivate) {
                // MESA PRIVADA: 100% va a la plataforma
                platformShare = data.rakeTotal;
                console.log(`[RAKE_LOCAL] 🔒 Mesa privada: 100% (${platformShare}) a plataforma.`);
            } else {
                // MESA PÚBLICA: Distribución 50/30/20 (platform/club/seller)
                // Si no hay club o seller, su parte va a la plataforma
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

            // 3. 💰 TRANSFERENCIA REAL AL ADMIN (¡CRÍTICO!)
            if (platformShare > 0) {
                // Verificar que el treasury user existe
                const treasuryDoc = await transaction.get(treasuryRef);
                if (!treasuryDoc.exists) {
                    console.error(`[RAKE_LOCAL] ❌ CRITICAL: Treasury user ${TREASURY_ADMIN_UID} not found!`);
                    throw new Error(`Treasury user ${TREASURY_ADMIN_UID} not found`);
                }

                transaction.update(treasuryRef, {
                    credit: admin.firestore.FieldValue.increment(platformShare),
                    lastRakeReceived: admin.firestore.FieldValue.serverTimestamp()
                });
                console.log(`[RAKE_LOCAL] 💵 Transfiriendo ${platformShare} al treasury ${TREASURY_ADMIN_UID}`);
            }

            // 4. TRANSFERIR A CLUB (si corresponde)
            if (clubShare > 0 && data.clubId) {
                const clubRef = db.collection('clubs').doc(data.clubId);
                const clubDoc = await transaction.get(clubRef);

                if (clubDoc.exists) {
                    transaction.update(clubRef, {
                        balance: admin.firestore.FieldValue.increment(clubShare),
                        totalRakeEarned: admin.firestore.FieldValue.increment(clubShare)
                    });
                    console.log(`[RAKE_LOCAL] 🏠 Club ${data.clubId} recibe ${clubShare}`);
                } else {
                    // Si el club no existe, el dinero va a la plataforma
                    platformShare += clubShare;
                    transaction.update(treasuryRef, {
                        credit: admin.firestore.FieldValue.increment(clubShare)
                    });
                    console.warn(`[RAKE_LOCAL] ⚠️ Club ${data.clubId} no existe. ${clubShare} redirigido a plataforma.`);
                }
            }

            // 5. TRANSFERIR A SELLER (si corresponde)
            if (sellerShare > 0 && data.sellerId) {
                const sellerRef = db.collection('users').doc(data.sellerId);
                const sellerDoc = await transaction.get(sellerRef);

                if (sellerDoc.exists) {
                    transaction.update(sellerRef, {
                        credit: admin.firestore.FieldValue.increment(sellerShare),
                        totalRakeEarned: admin.firestore.FieldValue.increment(sellerShare)
                    });
                    console.log(`[RAKE_LOCAL] 👤 Seller ${data.sellerId} recibe ${sellerShare}`);
                } else {
                    // Si el seller no existe, el dinero va a la plataforma
                    transaction.update(treasuryRef, {
                        credit: admin.firestore.FieldValue.increment(sellerShare)
                    });
                    console.warn(`[RAKE_LOCAL] ⚠️ Seller ${data.sellerId} no existe. ${sellerShare} redirigido a plataforma.`);
                }
            }

            // 6. REGISTRAR EN LEDGER (para auditoría)
            transaction.set(ledgerRef, {
                type: 'RAKE_COLLECTED',
                amount: data.rakeTotal,
                breakdown: {
                    platform: platformShare,
                    club: clubShare,
                    seller: sellerShare
                },
                tableId: data.tableId,
                handId: data.handId,
                isPrivate: !!data.isPrivate,
                clubId: data.clubId || null,
                sellerId: data.sellerId || null,
                winnerUid: data.winnerUid || null,
                potTotal: data.potTotal,
                processedAt: admin.firestore.FieldValue.serverTimestamp(),
                treasuryUid: TREASURY_ADMIN_UID,
                method: 'LOCAL_EXECUTION'
            });
        });

        const platformReceived = data.isPrivate ? data.rakeTotal : Math.floor(data.rakeTotal * 0.50);
        console.log(`[RAKE_LOCAL] ✅ Éxito: ${data.rakeTotal} procesados. Admin recibió: ${platformReceived}`);
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
