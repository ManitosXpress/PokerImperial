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

/**
 * onTableUpdate
 * Trigger para cerrar automáticamente el torneo cuando todas las mesas finalizan.
 */
export const onTableUpdate = functions.firestore
    .document('poker_tables/{tableId}')
    .onUpdate(async (change, context) => {
        const before = change.before.data();
        const after = change.after.data();

        // Detectar cambio a 'finished'
        // Usamos toLowerCase() para robustez
        const beforeStatus = (before.status || '').toLowerCase();
        const afterStatus = (after.status || '').toLowerCase();

        if (beforeStatus !== 'finished' && afterStatus === 'finished') {
            const tournamentId = after.tournamentId;

            // Solo proceder si es una mesa de torneo
            if (!tournamentId) return;

            if (!admin.apps.length) {
                admin.initializeApp();
            }
            const db = admin.firestore();

            // Consultar si quedan mesas activas para este torneo
            // Buscamos mesas que NO estén finished.
            // Firestore no soporta '!=' en queries fácilmente con otros filtros a veces, 
            // pero podemos buscar por los estados activos conocidos: 'active', 'playing', 'running'
            const activeTablesSnapshot = await db.collection('poker_tables')
                .where('tournamentId', '==', tournamentId)
                .where('status', 'in', ['active', 'playing', 'running', 'ACTIVE', 'PLAYING', 'RUNNING'])
                .get();

            if (activeTablesSnapshot.empty) {
                console.log(`All tables finished for tournament ${tournamentId}. Auto-closing tournament...`);

                // Ejecutar transacción para cerrar el torneo
                try {
                    await db.runTransaction(async (transaction) => {
                        const tournamentRef = db.collection('tournaments').doc(tournamentId);
                        const tournamentDoc = await transaction.get(tournamentRef);

                        if (!tournamentDoc.exists) return;

                        const currentStatus = (tournamentDoc.data()?.status || '').toUpperCase();

                        // Solo cerrar si no está ya cerrado
                        if (currentStatus !== 'FINISHED' && currentStatus !== 'COMPLETED') {
                            transaction.update(tournamentRef, {
                                status: 'FINISHED',
                                endedAt: admin.firestore.FieldValue.serverTimestamp()
                            });
                        }
                    });
                    console.log(`Tournament ${tournamentId} successfully closed.`);
                } catch (error) {
                    console.error(`Error auto-closing tournament ${tournamentId}:`, error);
                }
            } else {
                console.log(`Tournament ${tournamentId} still has ${activeTablesSnapshot.size} active tables.`);
            }
        }
    });
