import * as admin from 'firebase-admin';
import * as crypto from 'crypto';

// ------------------------------------------------------------------
// CONFIGURACIÓN
// ------------------------------------------------------------------
const GAME_SECRET = process.env.GAME_SECRET || 'default-secret-change-in-production-2024';
const CLUB_ID = 'club_test_01';
const SELLER_ID = 'user_seller_01';
const WINNER_ID = 'user_winner_01';
const TABLE_ID = 'table_test_01';

// Colores para consola
const CLR = {
    Reset: "\x1b[0m",
    Green: "\x1b[32m",
    Yellow: "\x1b[33m",
    Red: "\x1b[31m",
    Cyan: "\x1b[36m"
};

async function main() {
    console.log(`${CLR.Cyan}🧪 INICIANDO PRUEBA DE DISTRIBUCIÓN DE RAKE (SERVER AUTHORITY)${CLR.Reset}\n`);

    // 1. Inicializar Firebase
    try {
        const serviceAccountPath = '../../serviceAccountKey.json'; // Relative to src/scripts/
        let serviceAccount;

        try {
            serviceAccount = require(serviceAccountPath);
            console.log("🔑 Credenciales encontradas en serviceAccountKey.json");
        } catch (e) {
            console.log("⚠️ No se encontró serviceAccountKey.json, intentando usar credenciales por defecto...");
        }

        if (serviceAccount) {
            admin.initializeApp({
                credential: admin.credential.cert(serviceAccount)
            });
        } else {
            admin.initializeApp();
        }

        console.log("✅ Firebase Admin inicializado.");
    } catch (e) {
        console.error(`${CLR.Red}❌ Error inicializando Firebase. Asegúrate de tener las credenciales configuradas (GOOGLE_APPLICATION_CREDENTIALS).${CLR.Reset}`);
        process.exit(1);
    }

    const db = admin.firestore();

    // 2. Preparar Datos de Prueba (Escenario Controlado)
    console.log(`\n${CLR.Yellow}🛠️  Preparando escenario de prueba en Firestore...${CLR.Reset}`);

    try {
        // A. Crear Club
        await db.collection('clubs').doc(CLUB_ID).set({
            name: 'Test Club',
            walletBalance: 0, // Empezamos en 0 para verificar fácil
            ownerId: 'owner_test'
        });
        console.log(`   - Club ${CLUB_ID} reseteado (Balance: 0)`);

        // B. Crear Seller
        await db.collection('users').doc(SELLER_ID).set({
            email: 'seller@test.com',
            credit: 0, // Empezamos en 0
            role: 'seller'
        });
        console.log(`   - Seller ${SELLER_ID} reseteado (Credit: 0)`);

        // C. Crear Ganador (Vinculado a Club y Seller)
        await db.collection('users').doc(WINNER_ID).set({
            email: 'winner@test.com',
            credit: 1000,
            clubId: CLUB_ID,
            sellerId: SELLER_ID
        });
        console.log(`   - Winner ${WINNER_ID} creado (Linked to Club & Seller)`);

        // D. Crear Mesa Pública (IMPORTANTE: settleGameRound verifica isPublic)
        await db.collection('poker_tables').doc(TABLE_ID).set({
            isPublic: true,
            players: [
                { uid: WINNER_ID, id: WINNER_ID, name: 'Winner', chips: 500 }
            ]
        });
        console.log(`   - Mesa ${TABLE_ID} creada (Public: true)`);

    } catch (e) {
        console.error(`${CLR.Red}❌ Error preparando datos:${CLR.Reset}`, e);
        process.exit(1);
    }

    // 3. Generar Payload y Firma
    console.log(`\n${CLR.Yellow}🔐 Generando Payload Firmado...${CLR.Reset}`);

    const potTotal = 1000;
    const rakeTaken = 80; // 8%
    const netWin = potTotal - rakeTaken;

    const authPayload = {
        tableId: TABLE_ID,
        gameId: `test_hand_${Date.now()}`,
        winnerUid: WINNER_ID,
        potTotal: potTotal,
        rakeTaken: rakeTaken,
        finalPlayerStacks: {
            [WINNER_ID]: 500 + netWin // Simular que ganó el pot neto
        },
        timestamp: Date.now()
    };

    const payloadString = JSON.stringify(authPayload);
    const signature = crypto.createHmac('sha256', GAME_SECRET)
        .update(payloadString)
        .digest('hex');

    console.log(`   - Payload: ${payloadString}`);
    console.log(`   - Signature: ${signature.substring(0, 10)}...`);

    // 4. Escribir Trigger
    console.log(`\n${CLR.Yellow}🚀 Disparando Trigger (_trigger_settlement)...${CLR.Reset}`);

    await db.collection('_trigger_settlement').add({
        ...authPayload,
        authPayload: payloadString,
        signature: signature,
        timestamp: admin.firestore.FieldValue.serverTimestamp()
    });

    console.log("✅ Documento escrito. Esperando a Cloud Functions...");

    // 5. Monitoreo Activo (Polling)
    console.log(`\n${CLR.Cyan}👀 Monitoreando resultados (Timeout: 15s)...${CLR.Reset}`);

    let checks = 0;
    const maxChecks = 15;

    const interval = setInterval(async () => {
        checks++;
        process.stdout.write(".");

        // Verificar Club (Debe tener 24 fichas -> 30% de 80)
        const clubDoc = await db.collection('clubs').doc(CLUB_ID).get();
        const clubBalance = clubDoc.data()?.walletBalance || 0;

        // Verificar Seller (Debe tener 16 fichas -> 20% de 80)
        const sellerDoc = await db.collection('users').doc(SELLER_ID).get();
        const sellerCredit = sellerDoc.data()?.credit || 0;

        // Verificar System Stats (Debe haber aumentado, pero es compartido, difícil validar exacto sin leer antes)
        // Nos enfocamos en Club y Seller que estaban en 0.

        if (clubBalance === 24 && sellerCredit === 16) {
            clearInterval(interval);
            console.log(`\n\n${CLR.Green}🎉 ¡PRUEBA EXITOSA!${CLR.Reset}`);
            console.log(`   - Club Balance: ${clubBalance} (Esperado: 24) [30%]`);
            console.log(`   - Seller Credit: ${sellerCredit} (Esperado: 16) [20%]`);
            console.log(`   - Plataforma se llevó el resto (40) [50%]`);
            console.log(`\nEl sistema de Rake "Server Authority" funciona correctamente.`);
            process.exit(0);
        }

        if (checks >= maxChecks) {
            clearInterval(interval);
            console.log(`\n\n${CLR.Red}❌ TIMEOUT: Los saldos no se actualizaron a tiempo.${CLR.Reset}`);
            console.log(`   - Club Balance Actual: ${clubBalance} (Esperado: 24)`);
            console.log(`   - Seller Credit Actual: ${sellerCredit} (Esperado: 16)`);

            // Check for debug errors
            console.log(`\n${CLR.Yellow}🔍 Buscando errores en _debug_settlement_errors...${CLR.Reset}`);
            const errorsSnapshot = await db.collection('_debug_settlement_errors')
                .orderBy('timestamp', 'desc')
                .limit(1)
                .get();

            if (!errorsSnapshot.empty) {
                const errorData = errorsSnapshot.docs[0].data();
                console.log(`${CLR.Red}⚠️ ERROR ENCONTRADO:${CLR.Reset}`);
                console.log(JSON.stringify(errorData, null, 2));
            } else {
                console.log("No se encontraron errores recientes en la colección de debug.");

                // Check if trigger doc still exists
                const triggerDocs = await db.collection('_trigger_settlement').get();
                if (!triggerDocs.empty) {
                    console.log(`${CLR.Red}⚠️ EL DOCUMENTO TRIGGER AÚN EXISTE.${CLR.Reset}`);
                    console.log("Esto indica que la función NO se ejecutó o falló antes de borrarlo.");
                } else {
                    console.log("El documento trigger fue borrado (la función probablemente corrió pero no actualizó saldos).");
                }

                console.log("Revisa los logs de Firebase Functions para ver errores de sistema.");
            }

            process.exit(1);
        }

    }, 1000);
}

main();
