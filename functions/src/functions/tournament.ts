import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

/**
 * createTournament
 * Creates a new tournament with scope-based validation (GLOBAL or CLUB).
 * Only admins and club owners can create tournaments.
 */
export const createTournament = async (data: any, context: functions.https.CallableContext) => {
    if (!admin.apps.length) {
        admin.initializeApp();
    }
    const db = admin.firestore();
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
    }

    const {
        name,
        buyIn,
        scope,
        type,
        settings,
        clubId,
        numberOfTables, // 🆕 Recibimos numberOfTables
        finalTableMusic,
        finalTableTheme,
        description
    } = data;

    // Validaciones básicas
    if (!name || !buyIn || !scope || !type || !settings) {
        throw new functions.https.HttpsError('invalid-argument', 'Missing required fields: name, buyIn, scope, type, settings');
    }

    if (!['GLOBAL', 'CLUB'].includes(scope)) {
        throw new functions.https.HttpsError('invalid-argument', 'Invalid scope. Must be GLOBAL or CLUB.');
    }

    const validTypes = ['FREEZEOUT', 'REBUY', 'BOUNTY', 'TURBO'];
    if (!validTypes.includes(type)) {
        throw new functions.https.HttpsError('invalid-argument', `Invalid type. Must be one of ${validTypes.join(', ')}`);
    }

    if (!settings.blindSpeed || !['SLOW', 'NORMAL', 'TURBO'].includes(settings.blindSpeed)) {
        throw new functions.https.HttpsError('invalid-argument', 'Invalid blindSpeed. Must be SLOW, NORMAL, or TURBO.');
    }

    // Obtener el documento del usuario para verificar rol
    const userDoc = await db.collection('users').doc(context.auth.uid).get();
    const userData = userDoc.data();
    const userRole = context.auth.token.role || userData?.role;

    const isAdmin = userRole === 'admin';

    // Validación de Roles según Scope
    if (scope === 'GLOBAL') {
        const isClubOwner = userRole === 'club' || userRole === 'clubowner';
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
    const chatRoomId = db.collection('chats').doc().id; // Generar ID para chat room
    const timestamp = admin.firestore.FieldValue.serverTimestamp();

    // 🆕 Calcular estimatedPlayers basado en mesas (8-max por defecto)
    const tablesCount = numberOfTables || 1;
    const estimatedPlayerCount = tablesCount * 8;

    // 🆕 Pre-generar mesas
    const tableIds: string[] = [];
    const batch = db.batch();

    for (let i = 0; i < tablesCount; i++) {
        const tableId = db.collection('poker_tables').doc().id;
        tableIds.push(tableId);

        const newTable = {
            id: tableId,
            tournamentId: tournamentId,
            name: `Mesa ${i + 1} - Torneo ${name}`,
            smallBlind: 50, // TODO: Get from blind structure Level 1
            bigBlind: 100,
            minBuyIn: 0,
            maxBuyIn: 0,
            createdByClubId: clubId || null,
            createdByName: 'Tournament System',
            isPublic: false,
            isTournament: true,
            status: 'pending_tournament_start', // 🆕 Nuevo estado
            players: [],
            spectators: [],
            createdAt: timestamp,
            currentRound: null,
            pot: 0,
            communityCards: [],
            deck: [],
            dealerIndex: 0,
            currentTurnIndex: 0,
            lastActionTime: timestamp
        };

        const tableRef = db.collection('poker_tables').doc(tableId);
        batch.set(tableRef, newTable);
    }

    const newTournament: any = {
        id: tournamentId,
        name,
        description: description || '',
        buyIn: Number(buyIn),
        scope,
        type,
        settings: {
            rebuyAllowed: settings.rebuyAllowed || false,
            bountyAmount: settings.bountyAmount || 0,
            blindSpeed: settings.blindSpeed
        },
        prizePool: Number(buyIn) * estimatedPlayerCount, // Estimado inicial
        estimatedPlayers: estimatedPlayerCount,
        numberOfTables: tablesCount, // 🆕 Guardamos el número de mesas
        tableIds: tableIds, // 🆕 Guardamos los IDs de las mesas
        createdBy: context.auth.uid,
        status: 'REGISTERING',
        createdAt: timestamp,
        startTime: admin.firestore.Timestamp.fromDate(new Date(Date.now() + 24 * 60 * 60 * 1000)),
        registeredPlayerIds: [],
        chatRoomId: chatRoomId,
        // God Mode tracking fields
        isPaused: false,
        currentBlindLevel: 1,
        totalRakeCollected: 0,
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

    const tournamentRef = db.collection('tournaments').doc(tournamentId);
    batch.set(tournamentRef, newTournament);

    // Inicializar chat room si es necesario (opcional)
    // const chatRef = db.collection('chats').doc(chatRoomId);
    // batch.set(chatRef, { tournamentId, messages: [] });

    await batch.commit();

    return { success: true, tournamentId };
};

/**
 * registerForTournament
 * Permite a un usuario con rol PLAYER inscribirse en un torneo.
 * Deduce el buy-in de sus créditos y lo agrega a la lista de registrados.
 */
export const registerForTournament = async (data: any, context: functions.https.CallableContext) => {
    if (!admin.apps.length) {
        admin.initializeApp();
    }
    const db = admin.firestore();

    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
    }

    const { tournamentId } = data;

    if (!tournamentId) {
        throw new functions.https.HttpsError('invalid-argument', 'Tournament ID is required.');
    }

    const uid = context.auth.uid;

    // 1. Obtener datos del usuario
    const userDoc = await db.collection('users').doc(uid).get();
    if (!userDoc.exists) {
        throw new functions.https.HttpsError('not-found', 'User not found.');
    }

    const userData = userDoc.data();
    const userRole = context.auth.token.role || userData?.role;

    // 2. VALIDACIÓN DE ROL: Solo PLAYER puede jugar
    if (userRole !== 'player') {
        throw new functions.https.HttpsError(
            'permission-denied',
            'Solo los jugadores con rol PLAYER pueden inscribirse en torneos. Los dueños de club y administradores solo pueden organizar/observar.'
        );
    }

    // 3. Obtener datos del torneo
    const tournamentRef = db.collection('tournaments').doc(tournamentId);
    const tournamentDoc = await tournamentRef.get();

    if (!tournamentDoc.exists) {
        throw new functions.https.HttpsError('not-found', 'Tournament not found.');
    }

    const tournament = tournamentDoc.data();

    // 4. Validar estado del torneo (case-insensitive)
    const tournamentStatus = (tournament?.status || '').toString().toUpperCase();
    if (tournamentStatus !== 'REGISTERING' && tournamentStatus !== 'LATE_REG') {
        throw new functions.https.HttpsError(
            'failed-precondition',
            'Este torneo ya no acepta inscripciones.'
        );
    }

    // 5. Verificar si ya está registrado
    if (tournament?.registeredPlayerIds?.includes(uid)) {
        throw new functions.https.HttpsError(
            'already-exists',
            'Ya estás inscrito en este torneo.'
        );
    }

    // 6. Verificar créditos suficientes
    const userCredits = userData?.credit || 0;
    const buyIn = tournament?.buyIn || 0;

    if (userCredits < buyIn) {
        throw new functions.https.HttpsError(
            'failed-precondition',
            `Créditos insuficientes. Necesitas $${buyIn} pero tienes $${userCredits}.`
        );
    }

    // 7. Usar transacción para garantizar atomicidad
    try {
        await db.runTransaction(async (transaction) => {
            // Deducir buy-in
            transaction.update(userDoc.ref, {
                credit: admin.firestore.FieldValue.increment(-buyIn)
            });

            // Agregar a registeredPlayerIds (Mantener por compatibilidad temporal, pero la UI usará subcolección)
            transaction.update(tournamentRef, {
                registeredPlayerIds: admin.firestore.FieldValue.arrayUnion(uid),
                prizePool: admin.firestore.FieldValue.increment(buyIn)
            });

            // Agregar a subcolección participants
            const participantRef = tournamentRef.collection('participants').doc(uid);
            transaction.set(participantRef, {
                uid: uid,
                displayName: userData?.displayName || 'Unknown Player',
                photoURL: userData?.photoURL || null,
                joinedAt: admin.firestore.FieldValue.serverTimestamp(),
                chips: 0, // Chips iniciales se asignan al iniciar o son 0 en lobby
                status: 'registered'
            });

            // Crear entrada en ledger
            const ledgerRef = db.collection('financial_ledger').doc();
            transaction.set(ledgerRef, {
                type: 'TOURNAMENT_REGISTRATION',
                amount: buyIn,
                source: `user_${uid}`,
                destination: `tournament_${tournamentId}`,
                description: `Inscripción a torneo: ${tournament?.name}`,
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
                metadata: {
                    tournamentId,
                    tournamentName: tournament?.name,
                    uid
                }
            });
        });

        return {
            success: true,
            message: '¡Inscripción exitosa!',
            tournamentId,
            remainingCredits: userCredits - buyIn
        };
    } catch (error) {
        console.error('Error registering for tournament:', error);
        throw new functions.https.HttpsError('internal', 'Error al procesar la inscripción.');
    }
};

/**
 * unregisterFromTournament
 * Permite a un jugador cancelar su inscripción y recuperar su buy-in.
 * Solo disponible si el torneo aún no ha comenzado.
 */
export const unregisterFromTournament = async (data: any, context: functions.https.CallableContext) => {
    if (!admin.apps.length) {
        admin.initializeApp();
    }
    const db = admin.firestore();

    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
    }

    const { tournamentId } = data;

    if (!tournamentId) {
        throw new functions.https.HttpsError('invalid-argument', 'Tournament ID is required.');
    }

    const uid = context.auth.uid;

    // 1. Obtener datos del torneo
    const tournamentRef = db.collection('tournaments').doc(tournamentId);
    const tournamentDoc = await tournamentRef.get();

    if (!tournamentDoc.exists) {
        throw new functions.https.HttpsError('not-found', 'Tournament not found.');
    }

    const tournament = tournamentDoc.data();

    // 2. Validar estado del torneo (solo REGISTERING permite cancelar, case-insensitive)
    const tournamentStatus = (tournament?.status || '').toString().toUpperCase();
    if (tournamentStatus !== 'REGISTERING') {
        throw new functions.https.HttpsError(
            'failed-precondition',
            'No puedes cancelar tu inscripción una vez que el torneo ha comenzado.'
        );
    }

    // 3. Verificar que esté registrado
    if (!tournament?.registeredPlayerIds?.includes(uid)) {
        throw new functions.https.HttpsError(
            'failed-precondition',
            'No estás inscrito en este torneo.'
        );
    }

    const buyIn = tournament?.buyIn || 0;

    // 4. Usar transacción para refund
    try {
        await db.runTransaction(async (transaction) => {
            const userRef = db.collection('users').doc(uid);

            // Refund buy-in
            transaction.update(userRef, {
                credit: admin.firestore.FieldValue.increment(buyIn)
            });

            // Remover de registeredPlayerIds
            transaction.update(tournamentRef, {
                registeredPlayerIds: admin.firestore.FieldValue.arrayRemove(uid),
                prizePool: admin.firestore.FieldValue.increment(-buyIn)
            });

            // Remover de subcolección participants
            const participantRef = tournamentRef.collection('participants').doc(uid);
            transaction.delete(participantRef);

            // Crear entrada en ledger
            const ledgerRef = db.collection('financial_ledger').doc();
            transaction.set(ledgerRef, {
                type: 'TOURNAMENT_REFUND',
                amount: buyIn,
                source: `tournament_${tournamentId}`,
                destination: `user_${uid}`,
                description: `Reembolso de inscripción: ${tournament?.name}`,
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
                metadata: {
                    tournamentId,
                    tournamentName: tournament?.name,
                    uid
                }
            });
        });

        return {
            success: true,
            message: 'Inscripción cancelada. Buy-in reembolsado.',
            refundAmount: buyIn
        };
    } catch (error) {
        console.error('Error unregistering from tournament:', error);
        throw new functions.https.HttpsError('internal', 'Error al cancelar inscripción.');
    }
};

/**
 * startTournament
 * Starts the tournament, creates tables, and distributes players.
 * Only the host/owner can start the tournament.
 */
export const startTournament = async (data: any, context: functions.https.CallableContext) => {
    if (!admin.apps.length) {
        admin.initializeApp();
    }
    const db = admin.firestore();

    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
    }

    const { tournamentId } = data;
    const uid = context.auth.uid;

    if (!tournamentId) {
        throw new functions.https.HttpsError('invalid-argument', 'Tournament ID is required.');
    }

    // Usar transacción para garantizar atomicidad
    try {
        const result = await db.runTransaction(async (transaction) => {
            // 1. Get Tournament Data
            const tournamentRef = db.collection('tournaments').doc(tournamentId);
            const tournamentDoc = await transaction.get(tournamentRef);

            if (!tournamentDoc.exists) {
                throw new functions.https.HttpsError('not-found', 'Tournament not found.');
            }

            const tournament = tournamentDoc.data();

            // 2. Validate Permissions (Host/Owner/Admin)
            const userDoc = await transaction.get(db.collection('users').doc(uid));
            const userData = userDoc.data();
            const userRole = context.auth!.token.role || userData?.role;
            const isAdmin = userRole === 'admin';
            const isOwner = tournament?.createdBy === uid;

            if (!isAdmin && !isOwner) {
                throw new functions.https.HttpsError('permission-denied', 'Only the tournament host can start the tournament.');
            }

            // 3. Validate Status (case-insensitive)
            const tournamentStatus = (tournament?.status || '').toString().toUpperCase();
            if (tournamentStatus !== 'REGISTERING' && tournamentStatus !== 'LATE_REG') {
                throw new functions.https.HttpsError('failed-precondition', 'Tournament is not in a state to be started.');
            }

            // 4. Validate Player Count
            const MIN_PLAYERS = 2;
            const registeredPlayerIds = tournament?.registeredPlayerIds || [];
            if (registeredPlayerIds.length < MIN_PLAYERS) {
                throw new functions.https.HttpsError('failed-precondition', `Minimum ${MIN_PLAYERS} players required to start.`);
            }

            // 5. Create Tables and Distribute Players
            const maxPlayersPerTable = 8; // Eight-Max (8-max)
            const playerCount = registeredPlayerIds.length;
            // Cálculo Dinámico: Si hay 4 jugadores, debe ser 1 mesa.
            const requiredTableCount = playerCount === 0 ? 0 : Math.ceil(playerCount / maxPlayersPerTable);

            // Shuffle players for random seating
            const shuffledPlayers = [...registeredPlayerIds].sort(() => Math.random() - 0.5);

            // Fetch user profiles for table population
            const userRefs = shuffledPlayers.map((pid: string) => db.collection('users').doc(pid));
            const userSnapshots = await transaction.getAll(...userRefs);
            const userMap = new Map();
            userSnapshots.forEach(snap => {
                if (snap.exists) {
                    userMap.set(snap.id, snap.data());
                }
            });

            // --- REUSE EXISTING TABLES LOGIC ---
            // Fetch existing tables for this tournament
            // Note: We cannot perform a query inside a transaction if we didn't plan for it, 
            // but we can query by IDs if we have them in tournament.tableIds.
            // However, to be safe and robust, we should query all tables for this tournament.
            // Queries in transactions require the index to be built.
            const existingTablesQuery = await transaction.get(
                db.collection('poker_tables').where('tournamentId', '==', tournamentId)
            );

            const activeTableIds: string[] = [];
            const playerTableMap: { [key: string]: string } = {}; // Map { uid: tableId }

            let availableTables: any[] = [];
            if (!existingTablesQuery.empty) {
                availableTables = existingTablesQuery.docs.map(doc => ({ ref: doc.ref, data: doc.data(), id: doc.id }));
            }

            // We need 'requiredTableCount' tables.
            for (let i = 0; i < requiredTableCount; i++) {
                let tableId: string;
                let tableRef: any;
                let isNew = false;

                if (i < availableTables.length) {
                    // Reuse existing table
                    tableId = availableTables[i].id;
                    tableRef = availableTables[i].ref;
                } else {
                    // Create new table if not enough exist
                    tableRef = db.collection('poker_tables').doc();
                    tableId = tableRef.id;
                    isNew = true;
                }

                activeTableIds.push(tableId);

                // Determine players for this table
                const start = i * maxPlayersPerTable;
                const end = Math.min(start + maxPlayersPerTable, playerCount);
                const tablePlayerIds = shuffledPlayers.slice(start, end);

                const tablePlayers = tablePlayerIds.map((pid: string, index: number) => {
                    const uData = userMap.get(pid);
                    // Update map
                    playerTableMap[pid] = tableId;

                    return {
                        id: pid,
                        name: uData?.displayName || 'Unknown Player',
                        photoURL: uData?.photoURL || null,
                        chips: 10000, // TODO: Get from tournament settings
                        seat: index,
                        status: 'active'
                    };
                });

                const tableData = {
                    tournamentId: tournamentId,
                    name: `${tournament?.name} - Table ${i + 1}`,
                    smallBlind: 50, // TODO: Get from blind structure Level 1
                    bigBlind: 100,
                    minBuyIn: 0,
                    maxBuyIn: 0,
                    createdByClubId: tournament?.clubId || null,
                    createdByName: 'Tournament System',
                    isPublic: false,
                    isTournament: true,
                    status: 'active', // Set to active immediately
                    players: tablePlayers,
                    spectators: [],
                    // Only set createdAt if new, otherwise keep original
                    ...(isNew ? { createdAt: admin.firestore.FieldValue.serverTimestamp() } : {}),
                    currentRound: null,
                    pot: 0,
                    communityCards: [],
                    deck: [],
                    dealerIndex: 0,
                    currentTurnIndex: 0,
                    lastActionTime: admin.firestore.FieldValue.serverTimestamp()
                };

                if (isNew) {
                    transaction.set(tableRef, { id: tableId, ...tableData });
                } else {
                    transaction.update(tableRef, tableData);
                }
            }

            // 6. Update Tournament State
            transaction.update(tournamentRef, {
                status: 'active',
                activeTableIds: activeTableIds, // <--- CRÍTICO: Array de mesas activas
                tableIds: activeTableIds, // Keep legacy field in sync
                activeTableId: activeTableIds[0], // Legacy support for single table
                startTime: admin.firestore.FieldValue.serverTimestamp(),
                startedAt: admin.firestore.FieldValue.serverTimestamp(),
                totalTables: requiredTableCount,
                playerTableMap: playerTableMap // <--- CRÍTICO: Mapa { uid: tableId }
            });

            return { activeTableIds, playerTableMap };
        });

        console.log(`Tournament ${tournamentId} started with ${result.activeTableIds.length} tables.`);

        return {
            success: true,
            message: 'Tournament started successfully',
            tableIds: result.activeTableIds,
            activeTableIds: result.activeTableIds
        };

    } catch (error) {
        console.error('Error starting tournament:', error);
        throw new functions.https.HttpsError('internal', 'Error al iniciar el torneo: ' + error);
    }
};

/**
 * openTournamentTables
 * Opens all tables in a tournament for registration.
 * Changes status from 'pending_tournament_start' to 'active'.
 */
export const openTournamentTables = async (data: any, context: functions.https.CallableContext) => {
    if (!admin.apps.length) {
        admin.initializeApp();
    }
    const db = admin.firestore();

    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
    }

    const { tournamentId } = data;
    const uid = context.auth.uid;

    if (!tournamentId) {
        throw new functions.https.HttpsError('invalid-argument', 'Tournament ID is required.');
    }

    // 1. Get Tournament Data
    const tournamentRef = db.collection('tournaments').doc(tournamentId);
    const tournamentDoc = await tournamentRef.get();

    if (!tournamentDoc.exists) {
        throw new functions.https.HttpsError('not-found', 'Tournament not found.');
    }

    const tournament = tournamentDoc.data();

    // 2. Validate Permissions (Host/Owner/Admin)
    const userDoc = await db.collection('users').doc(uid).get();
    const userData = userDoc.data();
    const userRole = context.auth.token.role || userData?.role;
    const isAdmin = userRole === 'admin';
    const isOwner = tournament?.createdBy === uid;

    if (!isAdmin && !isOwner) {
        throw new functions.https.HttpsError('permission-denied', 'Only the tournament host can open tables.');
    }

    // 3. Fetch Tables
    const tablesSnapshot = await db.collection('poker_tables')
        .where('tournamentId', '==', tournamentId)
        .get();

    if (tablesSnapshot.empty) {
        throw new functions.https.HttpsError('not-found', 'No tables found for this tournament.');
    }

    // 4. Batch Update
    const batch = db.batch();

    tablesSnapshot.docs.forEach(doc => {
        batch.update(doc.ref, {
            status: 'active', // Open for players to join
            isPrivate: false // Make sure they are visible/accessible if needed, or keep private but accessible via lobby
        });
    });

    // Update Tournament Status
    batch.update(tournamentRef, {
        status: 'RUNNING', // Or 'active'
        startTime: admin.firestore.FieldValue.serverTimestamp()
    });

    await batch.commit();

    return {
        success: true,
        message: 'Tables opened successfully',
        tablesCount: tablesSnapshot.size
    };
};
