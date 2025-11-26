const admin = require('firebase-admin');

// Initialize Firebase Admin SDK
// Using Application Default Credentials from Firebase CLI login
admin.initializeApp({
    projectId: 'poker-fa33a'
});

const db = admin.firestore();
const auth = admin.auth();

/**
 * Migration Script: Create Firestore user documents for existing Firebase Auth users
 * 
 * This script:
 * 1. Lists all users from Firebase Authentication
 * 2. Creates corresponding user documents in Firestore
 * 3. Sets initial credit balance to 0
 * 4. Preserves email and display name from Auth
 */
async function migrateExistingUsers() {
    try {
        console.log('🚀 Starting user migration...\\n');

        // Get all users from Firebase Authentication
        const listUsersResult = await auth.listUsers();
        const users = listUsersResult.users;

        console.log(`📊 Found ${users.length} users in Firebase Authentication\\n`);

        let successCount = 0;
        let skipCount = 0;
        let errorCount = 0;

        // Process each user
        for (const user of users) {
            try {
                const uid = user.uid;

                // Check if user document already exists in Firestore
                const userDoc = await db.collection('users').doc(uid).get();

                if (userDoc.exists) {
                    console.log(`⏭️  Skipping ${user.email} - document already exists`);
                    skipCount++;
                    continue;
                }

                // Create user document
                const userData = {
                    uid: uid,
                    email: user.email || '',
                    displayName: user.displayName || user.email?.split('@')[0] || 'User',
                    photoURL: user.photoURL || '',
                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                    credit: 0, // Initial credit balance
                    lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
                };

                await db.collection('users').doc(uid).set(userData);

                console.log(`✅ Created user document for: ${user.email}`);
                console.log(`   - UID: ${uid}`);
                console.log(`   - Display Name: ${userData.displayName}`);
                console.log(`   - Initial Credit: ${userData.credit}\\n`);

                successCount++;

            } catch (error) {
                console.error(`❌ Error creating document for ${user.email}:`, error.message);
                errorCount++;
            }
        }

        // Summary
        console.log('\\n' + '='.repeat(50));
        console.log('📈 Migration Summary:');
        console.log(`   ✅ Successfully created: ${successCount} users`);
        console.log(`   ⏭️  Skipped (already exist): ${skipCount} users`);
        console.log(`   ❌ Errors: ${errorCount} users`);
        console.log('='.repeat(50) + '\\n');

        if (successCount > 0) {
            console.log('🎉 Migration completed successfully!');
            console.log('You can now view the users in Firestore Console:');
            console.log('https://console.firebase.google.com/project/poker-fa33a/firestore\\n');
        }

    } catch (error) {
        console.error('💥 Fatal error during migration:', error);
        process.exit(1);
    }
}

// Run the migration
migrateExistingUsers()
    .then(() => {
        console.log('✨ Script finished successfully');
        process.exit(0);
    })
    .catch((error) => {
        console.error('💥 Script failed:', error);
        process.exit(1);
    });
