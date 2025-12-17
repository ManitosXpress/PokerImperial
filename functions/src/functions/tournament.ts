import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

/**
 * createTournament
 * Creates a new tournament with scope-based validation (GLOBAL or CLUB).
 * Only admins and club owners can create tournaments.
 */
export const createTournament = async (data: any, context: functions.https.CallableContext) => {
    const db = admin.firestore();
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
    }

    const { name, buyIn, scope, speed, clubId, estimatedPlayers, finalTableMusic, finalTableTheme, description } = data;

    // Validaciones básicas
    if (!name || !buyIn || !scope || !speed) {
        throw new functions.https.HttpsError('invalid-argument', 'Missing required fields: name, buyIn, scope, speed');
    }

    if (!['GLOBAL', 'CLUB'].includes(scope)) {
        throw new functions.https.HttpsError('invalid-argument', 'Invalid scope. Must be GLOBAL or CLUB.');
    }

    if (!['TURBO', 'REGULAR', 'DEEP_STACK'].includes(speed)) {
        throw new functions.https.HttpsError('invalid-argument', 'Invalid speed. Must be TURBO, REGULAR, or DEEP_STACK.');
    }

    // Obtener el documento del usuario para verificar rol
    const userDoc = await db.collection('users').doc(context.auth.uid).get();
    const userData = userDoc.data();
    const userRole = context.auth.token.role || userData?.role;

    const isAdmin = userRole === 'admin';

    // Validación de Roles según Scope
    if (scope === 'GLOBAL') {
        const isClubOwner = userRole === 'club' || userRole === 'clubowner'; // Check for club owner role
        if (!isAdmin && !isClubOwner) {
            throw new functions.https.HttpsError(
                'permission-denied',
                'Only admins and club owners can create GLOBAL tournaments.'
            );
        }
    } else if (scope === 'CLUB') {
        if (!clubId) {
            throw new functions.https.HttpsError('invalid-argument', 'clubId required for CLUB tournaments.');
        }

        const clubDoc = await db.collection('clubs').doc(clubId).get();
        if (!clubDoc.exists) {
            throw new functions.https.HttpsError('not-found', 'Club not found.');
        }

        const clubData = clubDoc.data();
        // Permitir a admins crear torneos en cualquier club, o al owner del club
        if (!isAdmin && clubData?.ownerId !== context.auth.uid) {
            throw new functions.https.HttpsError(
                'permission-denied',
                'Only the club owner can create tournaments for this club.'
            );
        }
    }

    // Crear torneo
    const tournamentId = db.collection('tournaments').doc().id;
    const timestamp = admin.firestore.FieldValue.serverTimestamp();
    const estimatedPlayerCount = estimatedPlayers || 10;

    const newTournament: any = {
        id: tournamentId,
        name,
        description: description || '', // Default value
        buyIn: Number(buyIn),
        scope,
        speed,
        type: scope === 'GLOBAL' ? 'Open' : 'Club', // Compatibilidad con código legacy
        prizePool: Number(buyIn) * estimatedPlayerCount,
        estimatedPlayers: estimatedPlayerCount,
        createdBy: context.auth.uid,
        status: 'registering',
        createdAt: timestamp,
        startTime: admin.firestore.Timestamp.fromDate(new Date(Date.now() + 24 * 60 * 60 * 1000)),
        players: []
    };

    if (clubId) {
        newTournament.clubId = clubId;
    }

    if (finalTableMusic) {
        newTournament.finalTableMusic = finalTableMusic;
    }

    if (finalTableTheme) {
        newTournament.finalTableTheme = finalTableTheme;
    }

    await db.collection('tournaments').doc(tournamentId).set(newTournament);

    return { success: true, tournamentId };
};
