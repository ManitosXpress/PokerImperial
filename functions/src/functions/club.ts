import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

/**
 * createClub
 * Creates a new club.
 */
export const createClub = async (data: any, context: functions.https.CallableContext) => {
    const db = admin.firestore();
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
    }

    const { name, description } = data;
    if (!name) {
        throw new functions.https.HttpsError('invalid-argument', 'Club name is required.');
    }

    const userId = context.auth.uid;
    const clubId = db.collection('clubs').doc().id;
    const timestamp = admin.firestore.FieldValue.serverTimestamp();

    const newClub = {
        id: clubId,
        name,
        description: description || '',
        ownerId: userId,
        members: [userId],
        memberCount: 1,
        walletBalance: 0,
        createdAt: timestamp,
    };

    await db.collection('clubs').doc(clubId).set(newClub);

    // Update user's clubId
    await db.collection('users').doc(userId).update({
        clubId: clubId
    });

    return { success: true, clubId };
};

/**
 * joinClub
 * Adds a user to a club.
 */
export const joinClub = async (data: any, context: functions.https.CallableContext) => {
    const db = admin.firestore();
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
    }

    const { clubId } = data;
    if (!clubId) {
        throw new functions.https.HttpsError('invalid-argument', 'Club ID is required.');
    }

    const userId = context.auth.uid;
    const clubRef = db.collection('clubs').doc(clubId);

    await db.runTransaction(async (transaction) => {
        const clubDoc = await transaction.get(clubRef);
        if (!clubDoc.exists) {
            throw new functions.https.HttpsError('not-found', 'Club not found.');
        }

        const clubData = clubDoc.data();
        if (clubData?.members.includes(userId)) {
            throw new functions.https.HttpsError('already-exists', 'User is already a member.');
        }

        transaction.update(clubRef, {
            members: admin.firestore.FieldValue.arrayUnion(userId),
            memberCount: admin.firestore.FieldValue.increment(1)
        });

        transaction.update(db.collection('users').doc(userId), {
            clubId: clubId
        });
    });

    return { success: true };
};

/**
 * ownerCreateMember
 * Allows a club owner to create a new member (player or seller).
 */
export const ownerCreateMember = async (data: any, context: functions.https.CallableContext) => {
    const db = admin.firestore();
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
    }

    // Accept username instead of email
    const { username, password, displayName, role, clubId } = data;
    const ownerId = context.auth.uid;

    if (!username || !password || !role || !clubId) {
        throw new functions.https.HttpsError('invalid-argument', 'Missing required fields: username, password, role, clubId.');
    }

    // Generate email from username
    const email = `${username.toLowerCase()}@poker.app`;

    if (!['player', 'seller'].includes(role)) {
        throw new functions.https.HttpsError('invalid-argument', 'Invalid role. Must be player or seller.');
    }

    // Verify caller is the club owner
    const clubDoc = await db.collection('clubs').doc(clubId).get();
    if (!clubDoc.exists) {
        throw new functions.https.HttpsError('not-found', 'Club not found.');
    }

    if (clubDoc.data()?.ownerId !== ownerId) {
        throw new functions.https.HttpsError('permission-denied', 'Only the club owner can add members.');
    }

    try {
        // Create Authentication User
        const userRecord = await admin.auth().createUser({
            email,
            password,
            displayName: displayName || username,
            emailVerified: true, // Allow immediate login
        });

        const newUserId = userRecord.uid;
        const timestamp = admin.firestore.FieldValue.serverTimestamp();

        // Create User Document
        const newUser = {
            uid: newUserId,
            email,
            username, // Store username
            displayName: displayName || username,
            role, // 'player' or 'seller'
            clubId,
            credit: 0,
            createdAt: timestamp,
            lastUpdated: timestamp,
            createdBy: ownerId, // Track who created this user
            passwordChangeRequired: true, // Force password change on first login
        };

        await db.collection('users').doc(newUserId).set(newUser);

        // Add to Club Members list
        await db.collection('clubs').doc(clubId).update({
            members: admin.firestore.FieldValue.arrayUnion(newUserId),
            memberCount: admin.firestore.FieldValue.increment(1)
        });

        return { success: true, userId: newUserId, username, email };

    } catch (error: any) {
        console.error('Error creating member:', error);
        throw new functions.https.HttpsError('internal', error.message || 'Failed to create member.');
    }
};

/**
 * leaveClub
 * Removes a user from a club.
 */
export const leaveClub = async (data: any, context: functions.https.CallableContext) => {
    const db = admin.firestore();
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
    }

    const userId = context.auth.uid;
    
    // Get user's current clubId
    const userDoc = await db.collection('users').doc(userId).get();
    if (!userDoc.exists) {
        throw new functions.https.HttpsError('not-found', 'User not found.');
    }

    const userData = userDoc.data();
    const clubId = userData?.clubId;
    
    if (!clubId) {
        throw new functions.https.HttpsError('failed-precondition', 'User is not a member of any club.');
    }

    const clubRef = db.collection('clubs').doc(clubId);

    await db.runTransaction(async (transaction) => {
        const clubDoc = await transaction.get(clubRef);
        if (!clubDoc.exists) {
            throw new functions.https.HttpsError('not-found', 'Club not found.');
        }

        const clubData = clubDoc.data();
        
        // Check if user is the owner
        if (clubData?.ownerId === userId) {
            throw new functions.https.HttpsError('permission-denied', 'Club owner cannot leave the club. Transfer ownership first.');
        }

        // Check if user is a member
        if (!clubData?.members || !clubData.members.includes(userId)) {
            throw new functions.https.HttpsError('failed-precondition', 'User is not a member of this club.');
        }

        // Remove user from club members
        transaction.update(clubRef, {
            members: admin.firestore.FieldValue.arrayRemove(userId),
            memberCount: admin.firestore.FieldValue.increment(-1)
        });

        // Remove clubId from user document
        transaction.update(db.collection('users').doc(userId), {
            clubId: admin.firestore.FieldValue.delete()
        });
    });

    return { success: true };
};

/**
 * sellerCreatePlayer
 * Allows a seller to create a new player in their club.
 * - Can only create 'player' role (not seller or club)
 * - Auto-assigns clubId from seller's clubId
 * - Sets sellerId to track who recruited the player
 */
export const sellerCreatePlayer = async (data: any, context: functions.https.CallableContext) => {
    const db = admin.firestore();
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
    }

    // Accept username instead of email
    const { username, password, displayName, clubId } = data;
    const sellerId = context.auth.uid;

    if (!username || !password || !clubId) {
        throw new functions.https.HttpsError('invalid-argument', 'Missing required fields: username, password, clubId.');
    }

    // Generate email from username
    const email = `${username.toLowerCase()}@poker.app`;

    // Verify caller is a seller
    const sellerDoc = await db.collection('users').doc(sellerId).get();
    if (!sellerDoc.exists) {
        throw new functions.https.HttpsError('not-found', 'Seller profile not found.');
    }

    const sellerData = sellerDoc.data();
    if (sellerData?.role !== 'seller') {
        throw new functions.https.HttpsError('permission-denied', 'Only sellers can use this function.');
    }

    // Verify seller belongs to the same club
    if (sellerData?.clubId !== clubId) {
        throw new functions.https.HttpsError('permission-denied', 'You can only create players in your own club.');
    }

    try {
        // Create Authentication User
        const userRecord = await admin.auth().createUser({
            email,
            password,
            displayName: displayName || username,
            emailVerified: true, // Allow immediate login
        });

        const newUserId = userRecord.uid;
        const timestamp = admin.firestore.FieldValue.serverTimestamp();

        // Create User Document
        const newUser = {
            uid: newUserId,
            email,
            username, // Store username
            displayName: displayName || username,
            role: 'player', // Always player - sellers cannot create other sellers
            clubId,
            sellerId, // Track which seller recruited this player
            credit: 0,
            createdAt: timestamp,
            lastUpdated: timestamp,
            createdBy: sellerId,
            passwordChangeRequired: true, // Force password change on first login
        };

        await db.collection('users').doc(newUserId).set(newUser);

        // Add to Club Members list
        await db.collection('clubs').doc(clubId).update({
            members: admin.firestore.FieldValue.arrayUnion(newUserId),
            memberCount: admin.firestore.FieldValue.increment(1)
        });

        return { success: true, userId: newUserId, username, email };

    } catch (error: any) {
        console.error('Error creating player:', error);
        throw new functions.https.HttpsError('internal', error.message || 'Failed to create player.');
    }
};
