import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import { v4 as uuidv4 } from 'uuid';

const db = admin.firestore();

// Create an invitation link
export const createClubInvite = async (data: any, context: functions.https.CallableContext) => {
    // 1. Auth Check
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Must be authenticated.');
    }

    const { role, referenceName } = data;
    const callerId = context.auth.uid;

    // 2. Validate Input
    if (!role || !['seller', 'player'].includes(role)) {
        throw new functions.https.HttpsError('invalid-argument', 'Invalid role. Must be seller or player.');
    }
    if (!referenceName) {
        throw new functions.https.HttpsError('invalid-argument', 'Reference name is required.');
    }

    try {
        // 3. Get Caller's Club (Caller must be owner)
        // We assume the caller is a club owner. We need to find the club they own.
        // Option A: Pass clubId in data. Option B: Query clubs where ownerId == callerId.
        // Let's use Option B for security, or verify Option A.
        const clubsQuery = await db.collection('clubs').where('ownerId', '==', callerId).limit(1).get();

        if (clubsQuery.empty) {
            throw new functions.https.HttpsError('permission-denied', 'You do not own a club.');
        }

        const clubDoc = clubsQuery.docs[0];
        const clubId = clubDoc.id;
        const clubName = clubDoc.data().name;

        // 4. Generate Token
        const token = uuidv4();

        // 5. Save Invitation
        await db.collection('invitations').doc(token).set({
            token,
            clubId,
            clubName,
            role,
            referenceName,
            createdBy: callerId,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            status: 'pending', // pending, used, expired
            expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 7 * 24 * 60 * 60 * 1000) // 7 days
        });

        // 6. Return Link
        // In production, this should be a dynamic link or your app's URL
        // For now, we return the token and a constructed URL structure
        const inviteUrl = `https://poker-fa33a.web.app/setup?token=${token}`;

        return {
            success: true,
            inviteUrl,
            token
        };

    } catch (error) {
        console.error('Create Invite Error:', error);
        throw new functions.https.HttpsError('internal', 'Failed to create invite.');
    }
};

// Complete registration from invitation
export const completeInvitationRegistration = async (data: any, context: functions.https.CallableContext) => {
    const { token, email, password, displayName } = data;

    if (!token || !email || !password || !displayName) {
        throw new functions.https.HttpsError('invalid-argument', 'Missing required fields.');
    }

    try {
        // 1. Validate Token
        const inviteRef = db.collection('invitations').doc(token);
        const inviteDoc = await inviteRef.get();

        if (!inviteDoc.exists) {
            throw new functions.https.HttpsError('not-found', 'Invalid invitation code.');
        }

        const inviteData = inviteDoc.data();
        if (inviteData?.status !== 'pending') {
            throw new functions.https.HttpsError('failed-precondition', 'Invitation already used or expired.');
        }

        // Check expiration
        if (inviteData.expiresAt && inviteData.expiresAt.toMillis() < Date.now()) {
            throw new functions.https.HttpsError('failed-precondition', 'Invitation expired.');
        }

        // 2. Create Auth User
        const userRecord = await admin.auth().createUser({
            email,
            password,
            displayName
        });

        // 3. Create Firestore User with Role
        await db.collection('users').doc(userRecord.uid).set({
            uid: userRecord.uid,
            email,
            displayName,
            role: inviteData.role,
            clubId: inviteData.clubId,
            credit: 0, // Start with 0
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            invitedBy: inviteData.createdBy
        });

        // 4. Mark Invitation as Used
        await inviteRef.update({
            status: 'used',
            usedBy: userRecord.uid,
            usedAt: admin.firestore.FieldValue.serverTimestamp()
        });

        // 5. Update Club Member Count (Optional but good)
        await db.collection('clubs').doc(inviteData.clubId).update({
            memberCount: admin.firestore.FieldValue.increment(1)
        });

        return {
            success: true,
            userId: userRecord.uid,
            message: 'Account created successfully.'
        };

    } catch (error: any) {
        console.error('Complete Registration Error:', error);
        if (error.code === 'auth/email-already-exists') {
            throw new functions.https.HttpsError('already-exists', 'Email already in use.');
        }
        throw new functions.https.HttpsError('internal', 'Failed to complete registration.');
    }
};
