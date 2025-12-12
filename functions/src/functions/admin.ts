import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

// Lazy initialization de Firestore para evitar timeout en deploy
const getDb = () => {
    if (!admin.apps.length) {
        admin.initializeApp();
    }
    return admin.firestore();
};

const assertAdmin = (context: functions.https.CallableContext) => {
    // Basic check for auth
    if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Auth required.');
};

export const adminSetUserRole = async (data: any, context: functions.https.CallableContext) => {
    assertAdmin(context);
    const { targetUid, role } = data;
    if (!targetUid || !role) throw new functions.https.HttpsError('invalid-argument', 'Missing fields');
    
    try {
        const db = getDb();
        await db.collection('users').doc(targetUid).update({ role });
        return { success: true };
    } catch (error) {
        console.error('Error setting role:', error);
        throw new functions.https.HttpsError('internal', 'Failed to set user role.');
    }
};

/**
 * adminDeleteUser
 * Deletes a user from Firestore and optionally from Firebase Auth.
 * Requires admin privileges.
 */
export const adminDeleteUser = async (data: any, context: functions.https.CallableContext) => {
    assertAdmin(context);
    const { targetUid } = data;
    
    if (!targetUid) {
        throw new functions.https.HttpsError('invalid-argument', 'Missing targetUid.');
    }

    // Prevent self-deletion
    if (targetUid === context.auth?.uid) {
        throw new functions.https.HttpsError('permission-denied', 'Cannot delete your own account.');
    }

    try {
        const db = getDb();
        
        // Check if user exists
        const userRef = db.collection('users').doc(targetUid);
        const userDoc = await userRef.get();
        
        if (!userDoc.exists) {
            throw new functions.https.HttpsError('not-found', 'User not found in Firestore.');
        }

        // Delete user document and all sub-collections
        const batch = db.batch();
        
        // Delete sub-collections (like transactions)
        const subcollections = await userRef.listCollections();
        for (const subCol of subcollections) {
            const subColDocs = await subCol.get();
            for (const doc of subColDocs.docs) {
                batch.delete(doc.ref);
            }
        }
        
        // Delete the user document
        batch.delete(userRef);
        
        await batch.commit();

        // Optionally delete from Firebase Auth (requires admin privileges)
        try {
            await admin.auth().deleteUser(targetUid);
            console.log(`User ${targetUid} deleted from Auth and Firestore.`);
        } catch (authError: any) {
            // If Auth deletion fails, log but don't fail the whole operation
            console.warn(`Could not delete user from Auth: ${authError.message}. User document deleted from Firestore.`);
        }

        console.log(`Admin ${context.auth?.uid} deleted user ${targetUid}`);
        return { success: true, message: 'User deleted successfully.' };

    } catch (error: any) {
        console.error('Error deleting user:', error);
        
        // If it's already an HttpsError, re-throw it
        if (error instanceof functions.https.HttpsError) {
            throw error;
        }
        
        throw new functions.https.HttpsError('internal', `Failed to delete user: ${error.message}`);
    }
};

/**
 * adminMintCredits
 * Mints new credits to a user's wallet and logs to financial_ledger.
 * Use 'credits' only (plural).
 */
export const adminMintCredits = async (data: any, context: functions.https.CallableContext) => {
    assertAdmin(context);

    const { targetUid, amount } = data;
    if (!targetUid || typeof amount !== 'number' || amount <= 0) {
        throw new functions.https.HttpsError('invalid-argument', 'Invalid targetUid or amount.');
    }

    const db = getDb();
    const userRef = db.collection('users').doc(targetUid);
    const ledgerRef = db.collection('financial_ledger').doc();

    try {
        await db.runTransaction(async (transaction) => {
            const userDoc = await transaction.get(userRef);
            if (!userDoc.exists) {
                throw new functions.https.HttpsError('not-found', 'User not found.');
            }

            const userData = userDoc.data();
            // Consolidate on 'credits'
            const currentBalance = userData?.credit || userData?.credits || 0;
            const newCredit = currentBalance + amount;

            transaction.update(userRef, { 
                credit: newCredit,
                credits: admin.firestore.FieldValue.delete() // Remove the plural duplicate
            });

            // 2. Log to Ledger
            transaction.set(ledgerRef, {
                type: 'ADMIN_MINT',
                amount: amount,
                currency: 'CREDIT',
                fromId: 'SYSTEM_MINT',
                toId: targetUid,
                performedBy: context.auth?.uid,
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
                description: `Admin minted ${amount} credits for user ${targetUid}`
            });
            
            // 3. Update Total Circulation Counter
            const statsRef = db.collection('system_stats').doc('economy');
            transaction.set(statsRef, {
                totalCirculation: admin.firestore.FieldValue.increment(amount)
            }, { merge: true });
        });

        console.log(`Admin ${context.auth?.uid} minted ${amount} credits for ${targetUid}`);

        // --- N8N Webhook Trigger ---
        try {
            const webhookUrl = 'https://versatec.app.n8n.cloud/webhook/70426eb0-aa5d-4f48-92f1-7d71fa8b6d3e';
            const queryParams = new URLSearchParams({
                event: 'admin_mint',
                type: 'DEPOSIT', // Explicit type for n8n filter
                targetUid: targetUid,
                amount: amount.toString(),
                adminUid: context.auth?.uid || 'system',
                timestamp: new Date().toISOString()
            }).toString();

            // Using GET as per user screenshot configuration
            await fetch(`${webhookUrl}?${queryParams}`);
            console.log('N8N Webhook triggered successfully');
        } catch (error) {
            console.error('N8N Webhook failed:', error);
            // Non-blocking: We don't fail the operation if webhook fails
        }

        return { success: true };
    } catch (error) {
        console.error('Error minting credits:', error);
        throw new functions.https.HttpsError('internal', 'Failed to mint credits.');
    }
};

/**
 * getSystemStats
 * Returns aggregated system statistics.
 */
export const getSystemStats = async (data: any, context: functions.https.CallableContext) => {
    assertAdmin(context);

    try {
        const db = getDb();
        // 1. Count Users
        const usersSnapshot = await db.collection('users').count().get();
        const totalUsers = usersSnapshot.data().count;

        // 2. Active Tables
        const tablesSnapshot = await db.collection('poker_sessions').where('status', '==', 'active').count().get();
        const activeTables = tablesSnapshot.data().count;

        // 3. Total Circulation (Robust Calculation)
        // We sum 'credit' (singular) as requested
        let totalCirculation = 0;

        const allUsers = await db.collection('users').select('credit').get();
        
        allUsers.forEach(doc => {
            const d = doc.data();
            totalCirculation += (Number(d.credit) || 0);
        });

        // Update cache for reference
        await db.collection('system_stats').doc('economy').set({
            totalCirculation: totalCirculation,
            lastCalculated: admin.firestore.FieldValue.serverTimestamp()
        }, { merge: true });

        const economyDoc = await db.collection('system_stats').doc('economy').get();
        const accumulatedRake = economyDoc.data()?.accumulated_rake || 0;

        return {
            totalUsers,
            activeTables,
            totalCirculation,
            accumulatedRake
        };
    } catch (error) {
        console.error('Error getting stats:', error);
        throw new functions.https.HttpsError('internal', 'Failed to get stats.');
    }
};

export const bootstrapAdmin = async (data: any, context: functions.https.CallableContext) => {
    return { success: true };
};

/**
 * adminCreateUser
 * Allows admin to create a new user directly from the admin dashboard.
 * Sets createdAt and lastUpdated timestamps.
 */
export const adminCreateUser = async (data: any, context: functions.https.CallableContext) => {
    assertAdmin(context);
    
    const { username, password, displayName, role } = data;
    
    if (!username || !password || !displayName || !role) {
        throw new functions.https.HttpsError('invalid-argument', 'Missing required fields: username, password, displayName, role');
    }

    try {
        const db = getDb();
        const email = `${username}@poker.app`;
        
        // Create Authentication User
        const userRecord = await admin.auth().createUser({
            email,
            password,
            displayName,
            emailVerified: true,
        });

        const newUserId = userRecord.uid;
        const timestamp = admin.firestore.FieldValue.serverTimestamp();

        // Create User Document with createdAt and lastUpdated
        const newUser = {
            uid: newUserId,
            email,
            username,
            displayName,
            role,
            clubId: null, // Admin-created users don't have a club by default
            credit: 0,
            createdAt: timestamp,
            lastUpdated: timestamp,
            createdBy: context.auth?.uid, // Track which admin created this user
        };

        await db.collection('users').doc(newUserId).set(newUser);

        console.log(`Admin ${context.auth?.uid} created user ${newUserId} with role ${role}`);
        return { success: true, userId: newUserId, username, email };

    } catch (error: any) {
        console.error('Error creating user:', error);
        throw new functions.https.HttpsError('internal', `Failed to create user: ${error.message}`);
    }
};

/**
 * getUserTransactionHistory
 * Obtiene el historial completo de transacciones del usuario desde ambas colecciones:
 * - transaction_logs (transacciones tradicionales)
 * - financial_ledger (transacciones de juego, rake, etc.)
 * 
 * Combina, ordena y formatea todas las transacciones en un formato consistente.
 */
export const getUserTransactionHistory = async (data: any, context: functions.https.CallableContext) => {
    // Validación
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
    }

    const userId = context.auth.uid;
    const db = getDb();
    const limit = data?.limit || 100;

    try {
        // 1. Leer de transaction_logs (sin orderBy para evitar necesidad de índice)
        const transactionLogsSnapshot = await db.collection('transaction_logs')
            .where('userId', '==', userId)
            .get();

        // 2. Leer de financial_ledger (sin orderBy para evitar necesidad de índice)
        const financialLedgerSnapshot = await db.collection('financial_ledger')
            .where('userId', '==', userId)
            .get();

        // 3. Combinar y formatear transacciones
        const allTransactions: any[] = [];

        // Procesar transaction_logs
        for (const doc of transactionLogsSnapshot.docs) {
            const data = doc.data();
            allTransactions.push({
                id: doc.id,
                source: 'transaction_logs',
                type: data.type || 'unknown',
                amount: data.amount || 0,
                reason: data.reason || 'Sin descripción',
                timestamp: data.timestamp,
                metadata: data.metadata || {},
            });
        }

        // Procesar financial_ledger
        for (const doc of financialLedgerSnapshot.docs) {
            const data = doc.data();
            
            // Determinar amount según el tipo
            let amount = 0;
            if (data.type === 'GAME_WIN' || data.type === 'GAME_LOSS') {
                // Para GAME_WIN/GAME_LOSS, usar netAmount si existe, sino amount
                amount = data.netAmount || data.amount || 0;
            } else {
                amount = data.amount || 0;
            }

            allTransactions.push({
                id: doc.id,
                source: 'financial_ledger',
                type: data.type || 'unknown',
                amount: amount,
                reason: data.description || data.reason || 'Sin descripción',
                timestamp: data.timestamp,
                tableId: data.tableId || null,
                rakePaid: data.rakePaid || null,
                buyInAmount: data.buyInAmount || null,
                grossAmount: data.grossAmount || null,
            });
        }

        // 4. Ordenar por timestamp (más reciente primero)
        allTransactions.sort((a, b) => {
            const timestampA = a.timestamp?.toMillis() || 0;
            const timestampB = b.timestamp?.toMillis() || 0;
            return timestampB - timestampA;
        });

        // 5. Limitar resultados finales
        const finalTransactions = allTransactions.slice(0, limit);

        return {
            success: true,
            transactions: finalTransactions,
            total: finalTransactions.length
        };

    } catch (error: any) {
        console.error('Error getting transaction history:', error);
        throw new functions.https.HttpsError('internal', `Failed to get transaction history: ${error.message}`);
    }
};

/**
 * SCRIPT DE REPARACIÓN DE EMERGENCIA
 * 
 * Repara usuarios "bugeados" con el aviso de dinero en mesa que nunca desaparece.
 * 
 * Busca todos los usuarios con sesiones activas en poker_sessions (status: 'active')
 * pero que NO están en ninguna mesa activa, y fuerza la devolución de ese dinero
 * a su credit y limpia el error visual.
 * 
 * USO:
 * Llamar esta función HTTP una vez para reparar todos los usuarios afectados.
 * 
 * @returns Resumen de reparaciones realizadas
 */
export const repairStuckSessions = functions.https.onRequest(async (req, res) => {
    // Validar que sea una petición POST (por seguridad)
    if (req.method !== 'POST') {
        res.status(405).json({ error: 'Method not allowed. Use POST.' });
        return;
    }

    // Opcional: Validar token de admin (puedes agregar validación de auth si lo necesitas)
    // Por ahora, es una función HTTP pública que deberías proteger con Firebase Auth o API Key

    try {
        // Inicializar Admin si es necesario
        if (!admin.apps.length) {
            admin.initializeApp();
        }
        const db = admin.firestore();

        console.log('🔧 Iniciando reparación de sesiones atascadas...');

        // 1. Buscar todas las sesiones activas
        const activeSessionsSnapshot = await db.collection('poker_sessions')
            .where('status', '==', 'active')
            .get();

        console.log(`📊 Encontradas ${activeSessionsSnapshot.size} sesiones activas`);

        const repairResults: Array<{
            userId: string;
            sessionId: string;
            roomId: string;
            buyInAmount: number;
            currentChips: number;
            status: 'repaired' | 'skipped' | 'error';
            error?: string;
        }> = [];

        // 2. Para cada sesión, verificar si el usuario está en una mesa activa
        for (const sessionDoc of activeSessionsSnapshot.docs) {
            const sessionData = sessionDoc.data();
            const userId = sessionData.userId;
            const roomId = sessionData.roomId;
            const sessionId = sessionDoc.id;
            const buyInAmount = Number(sessionData.buyInAmount) || 0;
            const currentChips = Number(sessionData.currentChips) || buyInAmount;

            try {
                // Verificar si la mesa existe y está activa
                const tableDoc = await db.collection('poker_tables').doc(roomId).get();
                
                if (!tableDoc.exists) {
                    // Mesa no existe, sesión huérfana - REPARAR
                    console.log(`⚠️ Sesión huérfana encontrada: ${sessionId} (Mesa ${roomId} no existe)`);
                    await repairSession(db, userId, sessionId, roomId, currentChips, buyInAmount, 'table_not_found');
                    repairResults.push({
                        userId,
                        sessionId,
                        roomId,
                        buyInAmount,
                        currentChips,
                        status: 'repaired'
                    });
                    continue;
                }

                const tableData = tableDoc.data();
                const tableStatus = tableData?.status;
                const players = Array.isArray(tableData?.players) ? tableData.players : [];

                // Verificar si el usuario está en la lista de jugadores
                const playerInTable = players.some((p: any) => p.id === userId);

                if (tableStatus !== 'active' || !playerInTable) {
                    // Usuario no está en mesa activa - REPARAR
                    console.log(`⚠️ Sesión atascada encontrada: ${sessionId} (Usuario no en mesa activa)`);
                    await repairSession(db, userId, sessionId, roomId, currentChips, buyInAmount, 'user_not_in_active_table');
                    repairResults.push({
                        userId,
                        sessionId,
                        roomId,
                        buyInAmount,
                        currentChips,
                        status: 'repaired'
                    });
                } else {
                    // Usuario está en mesa activa - SKIP (no es un bug)
                    repairResults.push({
                        userId,
                        sessionId,
                        roomId,
                        buyInAmount,
                        currentChips,
                        status: 'skipped'
                    });
                }
            } catch (error: any) {
                console.error(`❌ Error procesando sesión ${sessionId}:`, error);
                repairResults.push({
                    userId,
                    sessionId,
                    roomId,
                    buyInAmount,
                    currentChips,
                    status: 'error',
                    error: error.message
                });
            }
        }

        // 3. Resumen
        const repaired = repairResults.filter(r => r.status === 'repaired').length;
        const skipped = repairResults.filter(r => r.status === 'skipped').length;
        const errors = repairResults.filter(r => r.status === 'error').length;

        console.log(`✅ Reparación completada:`);
        console.log(`   - Reparadas: ${repaired}`);
        console.log(`   - Omitidas (válidas): ${skipped}`);
        console.log(`   - Errores: ${errors}`);

        res.status(200).json({
            success: true,
            summary: {
                total: activeSessionsSnapshot.size,
                repaired,
                skipped,
                errors
            },
            details: repairResults
        });

    } catch (error: any) {
        console.error('❌ Error en script de reparación:', error);
        res.status(500).json({
            success: false,
            error: error.message || 'Unknown error'
        });
    }
});

/**
 * Función auxiliar para reparar una sesión individual
 */
async function repairSession(
    db: admin.firestore.Firestore,
    userId: string,
    sessionId: string,
    roomId: string,
    currentChips: number,
    buyInAmount: number,
    reason: string
): Promise<void> {
    // Calcular devolución (sin rake en reparación, devolvemos todo)
    // En una reparación de emergencia, devolvemos el buyInAmount original
    // o currentChips si es mayor (para no perder ganancias legítimas)
    const refundAmount = Math.max(currentChips, buyInAmount);

    await db.runTransaction(async (transaction) => {
        // 1. Leer usuario
        const userRef = db.collection('users').doc(userId);
        const userDoc = await transaction.get(userRef);

        if (!userDoc.exists) {
            throw new Error(`Usuario ${userId} no encontrado`);
        }

        // 2. Actualizar crédito del usuario
        transaction.update(userRef, {
            credit: admin.firestore.FieldValue.increment(refundAmount)
        });

        // 3. Cerrar sesión (esto elimina el indicador visual)
        const sessionRef = db.collection('poker_sessions').doc(sessionId);
        transaction.update(sessionRef, {
            status: 'completed',
            endTime: admin.firestore.FieldValue.serverTimestamp(),
            currentChips: currentChips,
            repairReason: reason,
            repairedAt: admin.firestore.FieldValue.serverTimestamp()
        });

        // 4. Registrar en ledger
        const ledgerRef = db.collection('financial_ledger').doc();
        transaction.set(ledgerRef, {
            type: 'REPAIR_REFUND',
            userId: userId,
            tableId: roomId,
            amount: refundAmount,
            buyInAmount: buyInAmount,
            currentChips: currentChips,
            reason: reason,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            description: `Reparación automática: Devolución de ${refundAmount} créditos (Sesión: ${sessionId}, Mesa: ${roomId})`
        });
    });

    console.log(`✅ Sesión ${sessionId} reparada: ${refundAmount} créditos devueltos a usuario ${userId}`);
}

/**
 * SCRIPT DE LIMPIEZA TOTAL DE FIRESTORE
 * 
 * ⚠️ ADVERTENCIA: Esta función ELIMINA TODA LA BASE DE DATOS.
 * Solo debe ser ejecutada por administradores y en casos extremos.
 * 
 * Elimina todas las colecciones y documentos de Firestore.
 * 
 * USO:
 * POST https://YOUR_REGION-YOUR_PROJECT.cloudfunctions.net/clearAllFirestoreData
 * 
 * Headers:
 * - Authorization: Bearer <ADMIN_TOKEN> (opcional, pero recomendado)
 * 
 * Body:
 * {
 *   "confirm": true,
 *   "password": "DELETE_ALL_DATA_2025" // Contraseña de seguridad
 * }
 */
export const clearAllFirestoreData = functions.https.onRequest(async (req, res) => {
    // Validar método POST
    if (req.method !== 'POST') {
        res.status(405).json({ error: 'Method not allowed. Use POST.' });
        return;
    }

    try {
        // Inicializar Admin si es necesario
        if (!admin.apps.length) {
            admin.initializeApp();
        }
        const db = admin.firestore();

        // Validar confirmación y contraseña
        const { confirm, password } = req.body;

        if (!confirm || confirm !== true) {
            res.status(400).json({
                error: 'Missing confirmation. Set "confirm": true in request body.',
                warning: 'This will DELETE ALL DATA in Firestore!'
            });
            return;
        }

        const SECURITY_PASSWORD = 'DELETE_ALL_DATA_2025'; // Cambia esto por una contraseña segura
        if (password !== SECURITY_PASSWORD) {
            res.status(403).json({
                error: 'Invalid password. This operation requires a security password.',
                hint: 'Contact the system administrator for the password.'
            });
            return;
        }

        console.log('⚠️ INICIANDO LIMPIEZA TOTAL DE FIRESTORE...');
        console.log('⚠️ ESTA OPERACIÓN ES IRREVERSIBLE!');

        // 1. Obtener todas las colecciones
        const collections = await db.listCollections();
        const collectionNames = collections.map(col => col.id);

        console.log(`📋 Colecciones encontradas: ${collectionNames.join(', ')}`);

        const deletionResults: Array<{
            collection: string;
            documentsDeleted: number;
            status: 'success' | 'error';
            error?: string;
        }> = [];

        // 2. Función recursiva para eliminar documentos y sub-colecciones
        const deleteCollection = async (collectionRef: admin.firestore.CollectionReference, collectionName: string): Promise<number> => {
            let totalDeleted = 0;
            const batchSize = 500;

            // Obtener todos los documentos
            let hasMore = true;
            let lastDoc: admin.firestore.QueryDocumentSnapshot | null = null;

            while (hasMore) {
                let query: admin.firestore.Query = collectionRef.limit(batchSize);
                
                // Si hay un último documento, empezar desde ahí (paginación)
                if (lastDoc) {
                    query = query.startAfter(lastDoc);
                }

                const snapshot = await query.get();

                if (snapshot.empty) {
                    hasMore = false;
                    break;
                }

                // Eliminar cada documento y sus sub-colecciones
                const batch = db.batch();
                
                for (const doc of snapshot.docs) {
                    // 1. Eliminar sub-colecciones del documento
                    const subCollections = await doc.ref.listCollections();
                    for (const subCol of subCollections) {
                        const subColDeleted = await deleteCollection(subCol, `${collectionName}/${doc.id}/${subCol.id}`);
                        totalDeleted += subColDeleted;
                        console.log(`   🗑️ Eliminada sub-colección ${subCol.id} del documento ${doc.id} (${subColDeleted} documentos)`);
                    }

                    // 2. Eliminar el documento
                    batch.delete(doc.ref);
                    totalDeleted++;
                    lastDoc = doc;
                }

                // Commit del batch
                await batch.commit();
                console.log(`   ✅ Procesados ${totalDeleted} documentos de ${collectionName}...`);

                // Si hay menos documentos que el batch size, terminamos
                if (snapshot.size < batchSize) {
                    hasMore = false;
                }
            }

            return totalDeleted;
        };

        // 3. Eliminar todas las colecciones y sus documentos (incluyendo sub-colecciones)
        for (const collectionRef of collections) {
            const collectionName = collectionRef.id;

            try {
                console.log(`🗑️ Eliminando colección: ${collectionName}`);

                const documentsDeleted = await deleteCollection(collectionRef, collectionName);

                deletionResults.push({
                    collection: collectionName,
                    documentsDeleted,
                    status: 'success'
                });

                console.log(`✅ Colección ${collectionName} eliminada completamente (${documentsDeleted} documentos incluyendo sub-colecciones)`);

            } catch (error: any) {
                console.error(`❌ Error eliminando colección ${collectionName}:`, error);
                deletionResults.push({
                    collection: collectionName,
                    documentsDeleted: 0,
                    status: 'error',
                    error: error.message
                });
            }
        }

        // 3. Resumen
        const totalDeleted = deletionResults.reduce((sum, r) => sum + r.documentsDeleted, 0);
        const successful = deletionResults.filter(r => r.status === 'success').length;
        const errors = deletionResults.filter(r => r.status === 'error').length;

        console.log(`\n✅ LIMPIEZA COMPLETADA:`);
        console.log(`   - Colecciones procesadas: ${collectionNames.length}`);
        console.log(`   - Colecciones eliminadas exitosamente: ${successful}`);
        console.log(`   - Errores: ${errors}`);
        console.log(`   - Total de documentos eliminados: ${totalDeleted}`);

        res.status(200).json({
            success: true,
            message: 'Firestore database cleared successfully',
            summary: {
                collectionsProcessed: collectionNames.length,
                collectionsDeleted: successful,
                errors: errors,
                totalDocumentsDeleted: totalDeleted
            },
            details: deletionResults,
            timestamp: admin.firestore.FieldValue.serverTimestamp()
        });

    } catch (error: any) {
        console.error('❌ Error en script de limpieza:', error);
        res.status(500).json({
            success: false,
            error: error.message || 'Unknown error',
            warning: 'Some data may have been deleted. Check the details.'
        });
    }
});

/**
 * SCRIPT DE LIMPIEZA DE BONO DE BIENVENIDA
 * 
 * Limpia usuarios de prueba que tienen exactamente 1000 créditos (bono de bienvenida)
 * y no tienen historial de transacciones reales.
 * 
 * Busca usuarios con:
 * - credit === 1000
 * - Sin transacciones en la sub-colección 'transactions' (o solo con transacción de 'Welcome Bonus')
 * 
 * Los resetea a 0 créditos.
 * 
 * USO:
 * POST https://YOUR_REGION-YOUR_PROJECT.cloudfunctions.net/cleanWelcomeBonusUsers
 * 
 * Body (opcional):
 * {
 *   "dryRun": true  // Si es true, solo muestra qué usuarios serían afectados sin hacer cambios
 * }
 * 
 * @returns Resumen de usuarios limpiados
 */
export const cleanWelcomeBonusUsers = functions.https.onRequest(async (req, res) => {
    // Validar método POST
    if (req.method !== 'POST') {
        res.status(405).json({ error: 'Method not allowed. Use POST.' });
        return;
    }

    try {
        const db = getDb();
        const dryRun = req.body?.dryRun === true;

        console.log(`\n🔍 Iniciando limpieza de usuarios con bono de bienvenida...`);
        console.log(`   Modo: ${dryRun ? 'DRY RUN (sin cambios)' : 'EJECUCIÓN REAL'}`);

        // Buscar todos los usuarios con credit === 1000
        const usersSnapshot = await db.collection('users')
            .where('credit', '==', 1000)
            .get();

        if (usersSnapshot.empty) {
            console.log('✅ No se encontraron usuarios con 1000 créditos.');
            res.status(200).json({
                success: true,
                message: 'No users found with 1000 credits.',
                cleaned: 0,
                dryRun: dryRun
            });
            return;
        }

        console.log(`   Encontrados ${usersSnapshot.size} usuarios con 1000 créditos.`);

        const usersToClean: Array<{ uid: string; email: string; displayName: string }> = [];
        const usersSkipped: Array<{ uid: string; reason: string }> = [];

        // Verificar cada usuario
        for (const userDoc of usersSnapshot.docs) {
            const userData = userDoc.data();
            const uid = userDoc.id;
            const email = userData.email || 'N/A';
            const displayName = userData.displayName || 'N/A';

            // Verificar transacciones
            const transactionsSnapshot = await db.collection('users')
                .doc(uid)
                .collection('transactions')
                .get();

            // Si no tiene transacciones, o solo tiene transacciones de "Welcome Bonus" o "system_refill"
            const hasRealTransactions = transactionsSnapshot.docs.some(doc => {
                const txData = doc.data();
                const reason = txData.reason || '';
                const type = txData.type || '';
                
                // Ignorar transacciones de bono de bienvenida o refill automático
                return !reason.includes('Welcome Bonus') && 
                       !reason.includes('Bankruptcy Protection Refill') &&
                       type !== 'system_refill';
            });

            if (hasRealTransactions) {
                usersSkipped.push({
                    uid,
                    reason: 'Tiene transacciones reales (no solo bono de bienvenida)'
                });
                console.log(`   ⏭️  Saltando ${email} (${displayName}): tiene transacciones reales`);
            } else {
                usersToClean.push({ uid, email, displayName });
                console.log(`   ✅ Usuario a limpiar: ${email} (${displayName})`);
            }
        }

        console.log(`\n📊 Resumen:`);
        console.log(`   - Usuarios a limpiar: ${usersToClean.length}`);
        console.log(`   - Usuarios saltados: ${usersSkipped.length}`);

        if (usersToClean.length === 0) {
            res.status(200).json({
                success: true,
                message: 'No users need cleaning. All users with 1000 credits have real transactions.',
                cleaned: 0,
                skipped: usersSkipped.length,
                dryRun: dryRun
            });
            return;
        }

        // Ejecutar limpieza
        if (!dryRun) {
            const batch = db.batch();
            let batchCount = 0;
            const maxBatchSize = 500; // Firestore limit

            for (const user of usersToClean) {
                const userRef = db.collection('users').doc(user.uid);
                batch.update(userRef, {
                    credit: 0,
                    lastUpdated: admin.firestore.FieldValue.serverTimestamp()
                });
                batchCount++;

                // Firestore tiene límite de 500 operaciones por batch
                if (batchCount >= maxBatchSize) {
                    await batch.commit();
                    batchCount = 0;
                    console.log(`   💾 Batch de ${maxBatchSize} usuarios guardado...`);
                }
            }

            // Commit del batch final si hay operaciones pendientes
            if (batchCount > 0) {
                await batch.commit();
            }

            console.log(`\n✅ LIMPIEZA COMPLETADA:`);
            console.log(`   - Usuarios limpiados: ${usersToClean.length}`);
            console.log(`   - Usuarios saltados: ${usersSkipped.length}`);
        } else {
            console.log(`\n🔍 DRY RUN - No se realizaron cambios`);
        }

        res.status(200).json({
            success: true,
            message: dryRun 
                ? 'Dry run completed. No changes made.' 
                : 'Welcome bonus users cleaned successfully.',
            cleaned: usersToClean.length,
            skipped: usersSkipped.length,
            dryRun: dryRun,
            cleanedUsers: usersToClean.map(u => ({
                uid: u.uid,
                email: u.email,
                displayName: u.displayName
            })),
            skippedUsers: usersSkipped
        });

    } catch (error: any) {
        console.error('❌ Error en script de limpieza de bono de bienvenida:', error);
        res.status(500).json({
            success: false,
            error: error.message || 'Unknown error',
            warning: 'Some users may have been cleaned. Check the logs.'
        });
    }
});