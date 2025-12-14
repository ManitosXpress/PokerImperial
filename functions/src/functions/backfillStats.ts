import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

/**
 * BACKFILL SCRIPT V2 - Recalcula Estadísticas Diarias
 * 
 * Versión Callable (onCall) para evitar timeouts de deployment
 * 
 * **CÓMO EJECUTAR desde Flutter/Web**:
 * ```dart
 * final callable = FirebaseFunctions.instance.httpsCallable('recalcDailyStatsCallable');
 * final result = await callable.call({'date': '2025-12-14'});
 * ```
 * 
 * **O desde cURL**:
 * ```bash
 * curl -X POST https://us-central1-poker-fa33a.cloudfunctions.net/recalcDailyStatsCallable \
 *   -H "Content-Type: application/json" \
 *   -d '{"data":{"date":"2025-12-14"}}'
 * ```
 */
export const recalcDailyStatsCallable = functions.https.onCall(async (data, context) => {
    const db = admin.firestore();

    // Obtener la fecha objetivo (default = hoy)
    const requestedDate = data?.date;
    let targetDate: Date;

    if (requestedDate) {
        targetDate = new Date(requestedDate);
        targetDate.setHours(0, 0, 0, 0);
    } else {
        targetDate = new Date();
        targetDate.setHours(0, 0, 0, 0);
    }

    const dateKey = targetDate.toISOString().split('T')[0];

    const dayStart = admin.firestore.Timestamp.fromDate(targetDate);
    const dayEnd = admin.firestore.Timestamp.fromDate(
        new Date(targetDate.getTime() + 24 * 60 * 60 * 1000)
    );

    console.log(`🔧 Recalculando estadísticas para ${dateKey}...`);

    try {
        const ledgerSnapshot = await db.collection('financial_ledger')
            .where('timestamp', '>=', dayStart)
            .where('timestamp', '<', dayEnd)
            .get();

        console.log(`📊 Encontradas ${ledgerSnapshot.size} transacciones`);

        let totalVolume = 0;
        let totalHands = 0;
        let totalRake = 0;
        let totalMint = 0;
        let totalBurn = 0;
        const activeUserIds = new Set<string>();

        for (const doc of ledgerSnapshot.docs) {
            const docData = doc.data();
            const type = docData.type;
            const amount = Math.abs(Number(docData.amount) || 0);
            const userId = docData.userId;

            if (userId && userId !== 'platform') {
                activeUserIds.add(userId);
            }

            switch (type) {
                case 'RAKE':
                    totalRake += amount;
                    break;
                case 'WIN_PRIZE':
                    totalHands++;
                    break;
                case 'BET':
                case 'ANTE':
                case 'BLIND':
                    totalVolume += amount;
                    break;
                case 'MINT':
                case 'DEPOSIT':
                case 'BONUS':
                    totalMint += amount;
                    break;
                case 'BURN':
                case 'WITHDRAWAL':
                    totalBurn += amount;
                    break;
            }
        }

        // Estimar volumen si no hay BETs registrados
        if (totalVolume === 0 && totalRake > 0) {
            totalVolume = Math.floor(totalRake / 0.08);
        }

        const statsDoc = {
            dateKey: dateKey,
            date: dayStart,
            totalVolume: totalVolume,
            totalHands: totalHands,
            totalRake: totalRake,
            dailyGGR: totalRake,
            totalMint: totalMint,
            totalBurn: totalBurn,
            activeUsers: activeUserIds.size,
            netFlow: totalMint - totalBurn,
            lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
            recalculated: true,
            recalculatedAt: admin.firestore.FieldValue.serverTimestamp()
        };

        await db.collection('stats_daily').doc(dateKey).set(statsDoc, { merge: true });

        console.log(`✅ Estadísticas guardadas para ${dateKey}`);

        return {
            success: true,
            dateKey: dateKey,
            transactionsProcessed: ledgerSnapshot.size,
            stats: {
                totalVolume: totalVolume,
                totalHands: totalHands,
                dailyGGR: totalRake,
                activeUsers: activeUserIds.size,
                totalMint: totalMint,
                totalBurn: totalBurn
            },
            message: `Estadísticas para ${dateKey} recalculadas exitosamente.`
        };

    } catch (error: any) {
        console.error(`❌ Error recalculando estadísticas:`, error);
        throw new functions.https.HttpsError('internal', error.message);
    }
});
