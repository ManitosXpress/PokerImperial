import * as admin from 'firebase-admin';

// Asegúrate de usar la instancia de firestore ya inicializada si existe, o admin.firestore()
// const db = admin.firestore(); // REMOVED: Causes "no-app" error on deployment if called before init

const getDb = () => {
    if (!admin.apps.length) {
        admin.initializeApp();
    }
    return admin.firestore();
};

export type EventType = 'BIG_POT' | 'TOURNAMENT_WIN' | 'TABLE_CREATED' | 'JACKPOT' | 'PLAYER_JOIN';

export interface FeedEventPayload {
    type: EventType;
    title: string;       // Ej: "Juan ganó 500 créditos"
    subtitle: string;    // Ej: "Mesa High Rollers - Escalera Real"
    amount?: number;     // Cantidad numérica para resaltar (opcional)
    clubId?: string;     // Si es null, es un evento global (PUBLIC). Si tiene ID, es privado del club.
    metadata?: Record<string, any>; // Ej: { tableId: '...', handId: '...' }
}

/**
 * Registra un evento en la colección 'live_feed'.
 * Acepta una transacción opcional para garantizar atomicidad con movimientos financieros.
 */
export async function logToLiveFeed(payload: FeedEventPayload, transaction?: FirebaseFirestore.Transaction) {
    const db = getDb();
    const eventRef = db.collection('live_feed').doc();

    const eventData = {
        ...payload,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        visibility: payload.clubId ? 'CLUB_ONLY' : 'PUBLIC',
        // TTL: El evento expira visualmente en 24 horas para no saturar queries
        expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 86400000)
    };

    try {
        if (transaction) {
            transaction.set(eventRef, eventData);
        } else {
            await eventRef.set(eventData);
        }
        console.log(`[LIVE_FEED] Event logged: ${payload.title}`);
    } catch (error) {
        console.error(`[LIVE_FEED] Error logging event:`, error);
        // No bloqueamos el flujo principal si falla el log, pero lo registramos.
    }
}
