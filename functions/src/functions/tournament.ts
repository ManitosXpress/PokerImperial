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
    }

    await db.collection('tournaments').doc(tournamentId).set(newTournament);

    return { success: true, tournamentId };
};
