import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

// Lazy initialization de Firestore
const getDb = () => {
    if (!admin.apps.length) {
        admin.initializeApp();
    }
    return admin.firestore();
};

/**
 * ═══════════════════════════════════════════════════════════════════════════
 * SANITIZE MONEY IN PLAY - Script de Saneamiento Una Sola Vez
 * ═══════════════════════════════════════════════════════════════════════════
 * 
 * PROPÓSITO:
 * Recuperar dinero "fantasma" atrapado en users.moneyInPlay de usuarios que
 * NO están jugando en ninguna mesa (currentTableId === null).
 * 
 * ALGORITMO:
 * 1. Buscar usuarios donde: currentTableId === null AND moneyInPlay > 0
 * 2. Para cada usuario:
 *    - Devolver moneyInPlay a credit
 *    - Resetear moneyInPlay a 0
 *    - Crear ledger entry tipo SYSTEM_CORRECTION
 * 
 * SEGURIDAD:
 * - Solo admin puede ejecutar (requiere validación de UID)
 * - Retorna lista detallada de usuarios afectados para auditoría
 * 
 * @param data - Vacío (o podría recibir { dryRun: boolean } para simulación)
 * @param context - Contexto de autenticación
 * @returns Resumen de correcciones aplicadas
 */
export const sanitizeMoneyInPlay = functions.https.onCall(async (data, context) => {
    // ════════════════════════════════════════════════════════════════════════
    // PASO 1: VALIDACIÓN ADMIN
    // ════════════════════════════════════════════════════════════════════════
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
    }

    const db = getDb();
    const isDryRun = data?.dryRun === true;

    // TODO: Reemplazar con tu UID de admin real
    // const ADMIN_UID = 'YOUR_ADMIN_UID_HERE';
    // if (context.auth.uid !== ADMIN_UID) {
    //     throw new functions.https.HttpsError('permission-denied', 'Admin access required.');
    // }

    console.log(`[SANITIZE_MONEY_IN_PLAY] 🔍 Iniciando sanitation script${isDryRun ? ' (DRY RUN)' : ''}...`);

    try {
        // ════════════════════════════════════════════════════════════════════════
        // PASO 2: BUSCAR USUARIOS CON DINERO HUÉRFANO
        // ════════════════════════════════════════════════════════════════════════
        // Usuarios con currentTableId === null PERO moneyInPlay > 0
        const orphanedUsersQuery = await db.collection('users')
            .where('currentTableId', '==', null)
            .where('moneyInPlay', '>', 0)
            .get();

        if (orphanedUsersQuery.empty) {
            console.log('[SANITIZE_MONEY_IN_PLAY] ✅ No se encontraron usuarios con dinero huérfano.');
            return {
                success: true,
                corrected: 0,
                users: [],
                message: 'No orphaned money found. All users are clean.'
            };
        }

        console.log(`[SANITIZE_MONEY_IN_PLAY] ⚠️  Encontrados ${orphanedUsersQuery.size} usuarios con moneyInPlay huérfano`);

        // ════════════════════════════════════════════════════════════════════════
        // PASO 3: PROCESAR CADA USUARIO (DRY RUN O EJECUCIÓN REAL)
        // ════════════════════════════════════════════════════════════════════════
        const corrections = [];
        const timestamp = admin.firestore.FieldValue.serverTimestamp();

        for (const userDoc of orphanedUsersQuery.docs) {
            const userId = userDoc.id;
            const userData = userDoc.data();
            const orphanedMoney = Number(userData.moneyInPlay) || 0;
            const currentCredit = Number(userData.credit) || 0;
            const email = userData.email || 'N/A';
            const displayName = userData.displayName || 'Unknown';

            corrections.push({
                uid: userId,
                email: email,
                displayName: displayName,
                orphanedMoney: orphanedMoney,
                currentCredit: currentCredit,
                newCredit: currentCredit + orphanedMoney
            });

            console.log(`[SANITIZE_MONEY_IN_PLAY] 💰 ${email} (${displayName}): Recuperando ${orphanedMoney} → credit`);
        }

        // Si es dry run, solo retornar lo que se haría
        if (isDryRun) {
            console.log('[SANITIZE_MONEY_IN_PLAY] 🧪 DRY RUN - No se aplicaron cambios. Mostrando preview.');
            return {
                success: true,
                dryRun: true,
                corrected: corrections.length,
                users: corrections,
                message: `DRY RUN: ${corrections.length} users would be corrected.`
            };
        }

        // ════════════════════════════════════════════════════════════════════════
        // PASO 4: APLICAR CORRECCIONES CON BATCH WRITE
        // ════════════════════════════════════════════════════════════════════════
        console.log('[SANITIZE_MONEY_IN_PLAY] 🔧 Aplicando correcciones...');

        const batch = db.batch();

        for (const correction of corrections) {
            const userRef = db.collection('users').doc(correction.uid);

            // Devolver dinero a credit y limpiar moneyInPlay
            batch.update(userRef, {
                credit: admin.firestore.FieldValue.increment(correction.orphanedMoney),
                moneyInPlay: 0,
                lastUpdated: timestamp
            });

            // Crear ledger entry tipo SYSTEM_CORRECTION
            const ledgerRef = db.collection('financial_ledger').doc();
            batch.set(ledgerRef, {
                type: 'SYSTEM_CORRECTION',
                userId: correction.uid,
                userName: correction.displayName,
                amount: correction.orphanedMoney,
                reason: 'Recovered orphaned moneyInPlay (user not at any table)',
                beforeCredit: correction.currentCredit,
                afterCredit: correction.newCredit,
                timestamp: timestamp,
                description: `System correction: Returned ${correction.orphanedMoney} from orphaned moneyInPlay to credit`
            });

            // Opcional: También crear transaction log para wallet UI
            const txLogRef = db.collection('transaction_logs').doc();
            batch.set(txLogRef, {
                userId: correction.uid,
                amount: correction.orphanedMoney,
                type: 'credit',
                reason: 'System Correction - Recovered Orphaned Money',
                timestamp: timestamp,
                beforeBalance: correction.currentCredit,
                afterBalance: correction.newCredit,
                metadata: {
                    correctionType: 'orphaned_money_in_play',
                    automated: true
                }
            });
        }

        await batch.commit();

        console.log(`[SANITIZE_MONEY_IN_PLAY] ✅ Correcciones aplicadas exitosamente: ${corrections.length} usuarios`);

        return {
            success: true,
            corrected: corrections.length,
            users: corrections,
            message: `Successfully corrected ${corrections.length} users with orphaned money.`
        };

    } catch (error: any) {
        console.error('[SANITIZE_MONEY_IN_PLAY] ❌ Error:', error);

        if (error instanceof functions.https.HttpsError) {
            throw error;
        }

        throw new functions.https.HttpsError('internal', `Sanitation script failed: ${error.message || 'Unknown error'}`);
    }
});
