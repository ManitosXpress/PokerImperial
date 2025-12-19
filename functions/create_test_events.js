const admin = require('firebase-admin');

// Initialize if not already initialized
if (!admin.apps.length) {
    admin.initializeApp();
}

const db = admin.firestore();

async function createTestEvents() {
    console.log('Creating test live feed events...');

    const events = [
        {
            type: 'big_win',
            playerName: 'Juan Pérez',
            amount: 5000,
            tableId: 'cash_table_001',
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
        },
        {
            type: 'huge_pot',
            playerName: 'María López',
            amount: 3200,
            tableId: 'cash_table_002',
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
        },
        {
            type: 'tournament_start',
            playerName: 'Torneo MTT Imperial',
            tableId: 'tournament_MTT_123',
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
        },
        {
            type: 'royal_flush',
            playerName: 'Carlos Ruiz',
            amount: 2500,
            tableId: 'cash_table_003',
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
        },
    ];

    for (const event of events) {
        const docRef = await db.collection('live_feed').add(event);
        console.log(`✅ Created event: ${docRef.id} - ${event.playerName}`);
    }

    console.log('All test events created!');
}

createTestEvents().catch(console.error);
