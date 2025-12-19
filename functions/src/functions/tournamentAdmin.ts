import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

/**
 * Security Helper: Verify Admin Access
 * Ensures only users with admin custom claim can execute God Mode functions
 */
function verifyAdminAccess(context: functions.https.CallableContext): void {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
    }

    const isAdmin = context.auth.token.admin === true;
    if (!isAdmin) {
        throw new functions.https.HttpsError(
            'permission-denied',
            'God Mode access requires admin privileges.'
        );
    }
}

/**
 * Blind Structure Definition
 * Maps blind levels to small/big blind values
 */
const BLIND_STRUCTURE: { [level: number]: { small: number; big: number } } = {
    1: { small: 50, big: 100 },
    2: { small: 100, big: 200 },
    3: { small: 150, big: 300 },
    4: { small: 200, big: 400 },
    5: { small: 300, big: 600 },
    6: { small: 400, big: 800 },
    7: { small: 500, big: 1000 },
    8: { small: 750, big: 1500 },
    9: { small: 1000, big: 2000 },
    10: { small: 1500, big: 3000 },
    11: { small: 2000, big: 4000 },
    12: { small: 3000, big: 6000 },
    13: { small: 4000, big: 8000 },
    14: { small: 5000, big: 10000 },
    15: { small: 10000, big: 20000 },
};

/**
 * Admin Pause Tournament
 * Freezes all tournament tables and notifies players
 */
export const adminPauseTournament = async (data: any, context: functions.https.CallableContext) => {
    verifyAdminAccess(context);

    const db = admin.firestore();
    const { tournamentId } = data;

    if (!tournamentId) {
        throw new functions.https.HttpsError('invalid-argument', 'Tournament ID is required.');
    }

    const tournamentRef = db.collection('tournaments').doc(tournamentId);
    const tournamentDoc = await tournamentRef.get();

    if (!tournamentDoc.exists) {
        throw new functions.https.HttpsError('not-found', 'Tournament not found.');
    }

    const tournament = tournamentDoc.data();

    if (tournament?.status !== 'RUNNING') {
        throw new functions.https.HttpsError('failed-precondition', 'Only running tournaments can be paused.');
    }

    // Update tournament status
    await tournamentRef.update({
        isPaused: true,
        pausedAt: admin.firestore.FieldValue.serverTimestamp()
    });

    // Send system broadcast message
    await db.collection('tournaments').doc(tournamentId).collection('messages').add({
        senderId: 'SYSTEM_ADMIN',
        senderName: '🛡️ ADMINISTRADOR',
        content: '⏸️ TORNEO PAUSADO POR EL ADMINISTRADOR',
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        isAdminBroadcast: true
    });

    return { success: true, message: 'Tournament paused successfully' };
};

/**
 * Admin Resume Tournament
 * Unfreezes tournament and resumes play
 */
export const adminResumeTournament = async (data: any, context: functions.https.CallableContext) => {
    verifyAdminAccess(context);

    const db = admin.firestore();
    const { tournamentId } = data;

    if (!tournamentId) {
        throw new functions.https.HttpsError('invalid-argument', 'Tournament ID is required.');
    }

    const tournamentRef = db.collection('tournaments').doc(tournamentId);
    const tournamentDoc = await tournamentRef.get();

    if (!tournamentDoc.exists) {
        throw new functions.https.HttpsError('not-found', 'Tournament not found.');
    }

    const tournament = tournamentDoc.data();

    if (!tournament?.isPaused) {
        throw new functions.https.HttpsError('failed-precondition', 'Tournament is not paused.');
    }

    // Resume tournament
    await tournamentRef.update({
        isPaused: false,
        resumedAt: admin.firestore.FieldValue.serverTimestamp()
    });

    // Send system broadcast message
    await db.collection('tournaments').doc(tournamentId).collection('messages').add({
        senderId: 'SYSTEM_ADMIN',
        senderName: '🛡️ ADMINISTRADOR',
        content: '▶️ TORNEO REANUDADO',
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        isAdminBroadcast: true
    });

    return { success: true, message: 'Tournament resumed successfully' };
};

/**
 * Admin Force Blind Level
 * Immediately advances tournament to next blind level
 * Updates all active tables with new blinds
 */
export const adminForceBlindLevel = async (data: any, context: functions.https.CallableContext) => {
    verifyAdminAccess(context);

    const db = admin.firestore();
    const { tournamentId } = data;

    if (!tournamentId) {
        throw new functions.https.HttpsError('invalid-argument', 'Tournament ID is required.');
    }

    const tournamentRef = db.collection('tournaments').doc(tournamentId);
    const tournamentDoc = await tournamentRef.get();

    if (!tournamentDoc.exists) {
        throw new functions.https.HttpsError('not-found', 'Tournament not found.');
    }

    const tournament = tournamentDoc.data();

    if (tournament?.status !== 'RUNNING') {
        throw new functions.https.HttpsError('failed-precondition', 'Only running tournaments can have blinds forced.');
    }

    const currentLevel = tournament?.currentBlindLevel || 1;
    const newLevel = currentLevel + 1;

    // Validate new level exists in structure
    if (!BLIND_STRUCTURE[newLevel]) {
        throw new functions.https.HttpsError(
            'out-of-range',
            `Maximum blind level reached (${currentLevel}). Cannot increase further.`
        );
    }

    const newBlinds = BLIND_STRUCTURE[newLevel];

    // Batch update: tournament + all tables
    const batch = db.batch();

    // Update tournament
    batch.update(tournamentRef, {
        currentBlindLevel: newLevel,
        lastBlindUpdate: admin.firestore.FieldValue.serverTimestamp()
    });

    // Update all tournament tables
    const tablesSnapshot = await db.collection('poker_tables')
        .where('tournamentId', '==', tournamentId)
        .where('status', '==', 'active')
        .get();

    tablesSnapshot.docs.forEach((tableDoc) => {
        batch.update(tableDoc.ref, {
            smallBlind: newBlinds.small,
            bigBlind: newBlinds.big
        });
    });

    await batch.commit();

    // Send system broadcast message
    await db.collection('tournaments').doc(tournamentId).collection('messages').add({
        senderId: 'SYSTEM_ADMIN',
        senderName: '🛡️ ADMINISTRADOR',
        content: `⏩ NIVEL DE CIEGAS FORZADO: ${newBlinds.small}/${newBlinds.big} (Nivel ${newLevel})`,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        isAdminBroadcast: true
    });

    return {
        success: true,
        message: 'Blind level forced successfully',
        newLevel,
        smallBlind: newBlinds.small,
        bigBlind: newBlinds.big
    };
};

/**
 * Admin Broadcast Message
 * Sends a global announcement to all tournament participants
 */
export const adminBroadcastMessage = async (data: any, context: functions.https.CallableContext) => {
    verifyAdminAccess(context);

    const db = admin.firestore();
    const { tournamentId, message } = data;

    if (!tournamentId || !message) {
        throw new functions.https.HttpsError('invalid-argument', 'Tournament ID and message are required.');
    }

    if (typeof message !== 'string' || message.trim().length === 0) {
        throw new functions.https.HttpsError('invalid-argument', 'Message must be a non-empty string.');
    }

    if (message.length > 500) {
        throw new functions.https.HttpsError('invalid-argument', 'Message must be 500 characters or less.');
    }

    const tournamentRef = db.collection('tournaments').doc(tournamentId);
    const tournamentDoc = await tournamentRef.get();

    if (!tournamentDoc.exists) {
        throw new functions.https.HttpsError('not-found', 'Tournament not found.');
    }

    // Send system broadcast message
    await db.collection('tournaments').doc(tournamentId).collection('messages').add({
        senderId: 'SYSTEM_ADMIN',
        senderName: '🛡️ ADMINISTRADOR',
        content: `📢 ${message.trim()}`,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        isAdminBroadcast: true
    });

    return { success: true, message: 'Broadcast sent successfully' };
};
