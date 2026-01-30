import * as admin from 'firebase-admin';

// CONFIGURACIÓN
const DRY_RUN = process.argv.includes('--dry-run');


async function main() {
    console.log(`🔧 REPAIR-BALANCES SCRIPT STARTED [${DRY_RUN ? 'DRY-RUN' : 'LIVE MODE'}]`);

    // Initialize Firebase Admin if not already
    if (!admin.apps.length) {
        admin.initializeApp();
        // Or provide service account if running locally outside of functions shell
    }

    const db = admin.firestore();
    const sessionsRef = db.collection('poker_sessions');
    const ledgerRef = db.collection('financial_ledger');
    const usersRef = db.collection('users');
    const tablesRef = db.collection('poker_tables');

    // 1. Scan for ACTIVE sessions
    console.log('🔍 Scanning for STUCK active sessions...');
    const snapshot = await sessionsRef.where('status', '==', 'active').get();

    if (snapshot.empty) {
        console.log('✅ No active sessions found. System healthy.');
        return;
    }

    console.log(`👉 Found ${snapshot.size} active sessions. Analyzing...`);

    let processedRequestCount = 0;
    let refundCount = 0;

    for (const doc of snapshot.docs) {
        const session = doc.data();
        const sessionId = doc.id;
        const { userId, roomId, currentChips, buyInAmount } = session;
        const uid = userId; // Alias

        if (!roomId || !uid) {
            console.warn(`⚠️ Skipping invalid session ${sessionId}: missing roomId or userId`);
            continue;
        }

        // 2. Check Table Status
        const tableDoc = await tablesRef.doc(roomId).get();
        let tableStatus = 'unknown';
        let tableExists = false;

        if (tableDoc.exists) {
            tableExists = true;
            tableStatus = tableDoc.data()?.status || 'unknown';
        } else {
            tableStatus = 'deleted';
        }

        // CONDICIÓN DE ERROR: Mesa no existe O Mesa finalizada
        const isStuck = !tableExists || tableStatus === 'finished' || tableStatus === 'inactive' || tableStatus === 'completed';

        if (!isStuck) {
            // Mesa activa, sesión activa -> CORRECTO (Probablemente)
            // Opcional: Verificar timeout (ej. > 24h)
            continue;
        }

        console.log(`🚩 ANOMALY DETECTED: Session ${sessionId} (User ${uid}) is ACTIVE but Table ${roomId} is ${tableStatus}`);

        // 3. Verify Ledger (Double Spending Check)
        // Buscamos si ya hubo una devolución para esta mesa/usuario
        const ledgerQuery = await ledgerRef
            .where('uid', '==', uid)
            .where('tableId', '==', roomId)
            .where('type', '==', 'TABLE_RETURN') // Adjust based on RoomManager types
            .limit(1)
            .get();

        if (!ledgerQuery.empty) {
            console.log(`⚠️ Refund already processed for ${uid} in ${roomId}. Marking session as completed manually.`);
            if (!DRY_RUN) {
                await sessionsRef.doc(sessionId).update({
                    status: 'completed',
                    closedReason: 'manual_repair_already_refunded',
                    lastUpdated: admin.firestore.FieldValue.serverTimestamp()
                });
            }
            continue;
        }

        // 4. Calculate Refund Amount
        // Prefer currentChips if available and trustworthy, else fallback to buyInAmount?
        // WARNING: currentChips might be outdated if server crashed.
        // Pero es mejor que nada.
        const refundAmount = currentChips || buyInAmount || 0;

        if (refundAmount <= 0) {
            console.log(`⚠️ No funds to refund for ${uid}. Marking session completed.`);
            if (!DRY_RUN) {
                await sessionsRef.doc(sessionId).update({
                    status: 'completed',
                    closedReason: 'manual_repair_zero_balance',
                    lastUpdated: admin.firestore.FieldValue.serverTimestamp()
                });
            }
            continue;
        }

        console.log(`💰 REFUND NEEDED: ${uid} -> ${refundAmount} chips`);

        if (!DRY_RUN) {
            try {
                await db.runTransaction(async (transaction) => {
                    // Update User
                    const userDocRef = usersRef.doc(uid);
                    transaction.update(userDocRef, {
                        moneyInPlay: 0,
                        currentTableId: null,
                        credit: admin.firestore.FieldValue.increment(refundAmount),
                        lastUpdated: admin.firestore.FieldValue.serverTimestamp()
                    });

                    // Update Session
                    const sessionDocRef = sessionsRef.doc(sessionId);
                    transaction.update(sessionDocRef, {
                        status: 'completed',
                        endTime: admin.firestore.FieldValue.serverTimestamp(),
                        closedReason: 'manual_repair_script',
                        refundedAmount: refundAmount
                    });

                    // Ledger Entry
                    const newLedgerRef = ledgerRef.doc();
                    transaction.set(newLedgerRef, {
                        type: 'CREDIT_ADJUSTMENT', // DISTINCT TYPE FOR MANUAL REPAIR
                        uid: uid,
                        tableId: roomId,
                        sessionId: sessionId,
                        amount: refundAmount,
                        timestamp: admin.firestore.FieldValue.serverTimestamp(),
                        description: `Emergency Refund for stuck session in table ${roomId}`,
                        reason: `Table status: ${tableStatus}`
                    });
                });
                console.log(`✅ REFUND SUCCESSFUL for ${uid}`);
                refundCount++;
            } catch (err) {
                console.error(`❌ REFUND FAILED for ${uid}:`, err);
            }
        }
        processedRequestCount++;
    }

    console.log(`\n🏁 REPAIR COMPLETE.`);
    console.log(`   - Sessions Analyzed: ${snapshot.size}`);
    console.log(`   - Refunds Processed: ${refundCount}`);
    console.log(`   - Mode: ${DRY_RUN ? 'DRY-RUN (No changes made)' : 'LIVE (Changes applied)'}`);
}

main().catch(console.error);
