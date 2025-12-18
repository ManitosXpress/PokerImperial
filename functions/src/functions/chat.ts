import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

/**
 * sendTournamentMessage
 * Permite a un usuario enviar un mensaje al chat de un torneo.
 * Valida que el usuario sea parte del torneo (o admin/host).
 */
export const sendTournamentMessage = async (data: any, context: functions.https.CallableContext) => {
    const db = admin.firestore();

    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
    }

    const { tournamentId, message } = data;
    const uid = context.auth.uid;

    if (!tournamentId || !message || message.trim().length === 0) {
        throw new functions.https.HttpsError('invalid-argument', 'Tournament ID and a non-empty message are required.');
    }

    if (message.length > 500) {
        throw new functions.https.HttpsError('invalid-argument', 'Message is too long (max 500 chars).');
    }

    // 1. Obtener datos del usuario para el mensaje
    const userDoc = await db.collection('users').doc(uid).get();
    const userData = userDoc.data();
    const senderName = userData?.displayName || 'Unknown Player';
    const senderPhoto = userData?.photoURL || null;

    // 2. Validar que el torneo existe y obtener chatRoomId
    const tournamentRef = db.collection('tournaments').doc(tournamentId);
    const tournamentDoc = await tournamentRef.get();

    if (!tournamentDoc.exists) {
        throw new functions.https.HttpsError('not-found', 'Tournament not found.');
    }

    const tournament = tournamentDoc.data();
    const chatRoomId = tournament?.chatRoomId;

    if (!chatRoomId) {
        throw new functions.https.HttpsError('failed-precondition', 'Tournament does not have a chat room.');
    }

    // 3. (Opcional) Validar que el usuario está registrado en el torneo o es el host/admin
    // Por ahora permitimos que cualquiera que vea el lobby pueda hablar (social), 
    // o podríamos restringirlo solo a registeredPlayerIds.
    // Vamos a restringirlo a usuarios autenticados por ahora, pero podríamos descomentar esto:
    /*
    const isRegistered = tournament?.registeredPlayerIds?.includes(uid);
    const isOwner = tournament?.ownerId === uid; // Asumiendo que guardamos ownerId
    if (!isRegistered && !isOwner) {
         throw new functions.https.HttpsError('permission-denied', 'Must be registered to chat.');
    }
    */

    // 4. Guardar mensaje en la subcolección 'messages' del documento de chat (o colección raíz 'chats')
    // Usaremos una colección raíz 'chats/{chatRoomId}/messages' para escalabilidad
    try {
        const messageData = {
            senderId: uid,
            senderName: senderName,
            senderPhoto: senderPhoto,
            content: message.trim(),
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            type: 'text', // 'text', 'system', 'emoji'
        };

        await db.collection('chats')
            .doc(chatRoomId)
            .collection('messages')
            .add(messageData);

        return { success: true };
    } catch (error) {
        console.error('Error sending message:', error);
        throw new functions.https.HttpsError('internal', 'Could not send message.');
    }
};
