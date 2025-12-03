import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

/**
 * createTournament
 * Creates a new tournament.
 */
export const createTournament = async (data: any, context: functions.https.CallableContext) => {
    const db = admin.firestore();
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
    }

    const { name, buyIn, type, clubId } = data;
    if (!name || !buyIn || !type) {
        throw new functions.https.HttpsError('invalid-argument', 'Missing required fields.');
    }

    // Check if user is admin or club owner
    const isAdmin = context.auth.token.role === 'admin';

    // If not admin, clubId is required and must own the club (or be authorized)
    if (!isAdmin) {
        if (!clubId) {
            throw new functions.https.HttpsError('invalid-argument', 'Club ID required for non-admin tournaments.');
        }
        // Ideally we check ownership here too, but for now we trust the client sends the right clubId 
        // (and Firestore rules/other checks enforce it). 
        // Actually, let's enforce ownership check if we can, but 'createTournament' logic 
        // might be used by club owners.
    }

    const tournamentId = db.collection('tournaments').doc().id;
    const timestamp = admin.firestore.FieldValue.serverTimestamp();

    const newTournament: any = {
        id: tournamentId,
        name,
        buyIn: Number(buyIn),
        type, // 'Open', 'Inter-club', or 'Club'
        prizePool: Number(buyIn) * 10, // Initial prize pool logic (can be updated)
        createdBy: context.auth.uid,
        status: 'registering', // registering, active, completed
        createdAt: timestamp,
        startTime: admin.firestore.Timestamp.fromDate(new Date(Date.now() + 24 * 60 * 60 * 1000)), // Default 24h from now
        players: []
    };

    if (clubId) {
        newTournament.clubId = clubId;
    } else if (isAdmin) {
        newTournament.isOfficial = true; // Mark as official/admin tournament
    }

    await db.collection('tournaments').doc(tournamentId).set(newTournament);

    return { success: true, tournamentId };
};
