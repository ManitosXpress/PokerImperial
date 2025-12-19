import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

/**
 * onTournamentFinish
 * Trigger que se ejecuta cuando un torneo cambia a estado 'completed'
 * Actualiza las estadísticas del club automáticamente
 */
export const onTournamentFinish = functions.firestore
    .document('tournaments/{tournamentId}')
    .onUpdate(async (change, context) => {
        const before = change.before.data();
        const after = change.after.data();

        // Detectar cuando un torneo pasa a 'FINISHED'
        if (before.status !== 'FINISHED' && after.status === 'FINISHED') {
            if (!admin.apps.length) {
                admin.initializeApp();
            }
            const db = admin.firestore();
            const { clubId, prizePool } = after;

            if (!clubId) {
                // Solo actualizar estadísticas para torneos de club
                return;
            }

            // Actualizar estadísticas del club
            const clubStatsRef = db.collection('clubs').doc(clubId).collection('stats').doc('tournaments');

            // Incrementar contador de torneos
            await clubStatsRef.set({
                tournamentsHosted: admin.firestore.FieldValue.increment(1),
            }, { merge: true });

            // Actualizar biggest pot si es mayor
            const statsDoc = await clubStatsRef.get();
            const currentBiggest = statsDoc.data()?.biggestPot || 0;

            if (prizePool > currentBiggest) {
                await clubStatsRef.update({
                    biggestPot: prizePool
                });
            }

            console.log(`Tournament ${context.params.tournamentId} completed. Club ${clubId} stats updated.`);
        }
    });
