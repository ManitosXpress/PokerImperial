const admin = require('firebase-admin');
const readline = require('readline');
const path = require('path');
const fs = require('fs');

// Initialize Firebase Admin SDK
// Intenta múltiples métodos de autenticación
let db;

try {
    // Método 1: Intentar con serviceAccountKey.json (si existe)
    const serviceAccountPath = path.join(__dirname, 'serviceAccountKey.json');
    const serverServiceAccountPath = path.join(__dirname, 'server', 'serviceAccountKey.json');
    
    if (fs.existsSync(serviceAccountPath)) {
        console.log('🔑 Usando serviceAccountKey.json de la raíz del proyecto...');
        admin.initializeApp({
            credential: admin.credential.cert(serviceAccountPath),
            projectId: 'poker-fa33a'
        });
        db = admin.firestore();
        console.log('✅ Firebase Admin inicializado con serviceAccountKey.json\n');
    } else if (fs.existsSync(serverServiceAccountPath)) {
        console.log('🔑 Usando serviceAccountKey.json del directorio server...');
        admin.initializeApp({
            credential: admin.credential.cert(serverServiceAccountPath),
            projectId: 'poker-fa33a'
        });
        db = admin.firestore();
        console.log('✅ Firebase Admin inicializado con serviceAccountKey.json\n');
    } else {
        // Método 2: Intentar con Application Default Credentials (firebase login)
        console.log('🔑 Intentando usar Application Default Credentials (firebase login)...');
        console.log('   Si falla, ejecuta: firebase login\n');
        admin.initializeApp({
            projectId: 'poker-fa33a'
        });
        db = admin.firestore();
        console.log('✅ Firebase Admin inicializado con Application Default Credentials\n');
    }
} catch (error) {
    console.error('\n❌ Error al inicializar Firebase Admin:', error.message);
    console.error('\n💡 Soluciones posibles:');
    console.error('   1. Ejecuta: firebase login');
    console.error('   2. O coloca serviceAccountKey.json en la raíz del proyecto');
    console.error('   3. O coloca serviceAccountKey.json en el directorio server/');
    console.error('\n📖 Para obtener serviceAccountKey.json:');
    console.error('   - Ve a: https://console.firebase.google.com/project/poker-fa33a/settings/serviceaccounts/adminsdk');
    console.error('   - Haz clic en "Generar nueva clave privada"');
    console.error('   - Guarda el archivo como serviceAccountKey.json\n');
    process.exit(1);
}

/**
 * Script para limpiar toda la base de datos EXCEPTO la colección 'users'
 * 
 * Este script:
 * 1. Lista todas las colecciones en Firestore
 * 2. Preserva la colección 'users' con todos sus documentos y créditos
 * 3. Elimina todas las demás colecciones y sus sub-colecciones
 * 4. Muestra un resumen detallado de lo eliminado
 * 
 * ⚠️ ADVERTENCIA: Esta operación es IRREVERSIBLE
 */

// Función para pedir confirmación al usuario
function askConfirmation(question) {
    const rl = readline.createInterface({
        input: process.stdin,
        output: process.stdout
    });

    return new Promise((resolve) => {
        rl.question(question, (answer) => {
            rl.close();
            resolve(answer.toLowerCase().trim());
        });
    });
}

// Función recursiva para eliminar documentos y sub-colecciones
async function deleteCollection(collectionRef, collectionName) {
    let totalDeleted = 0;
    const batchSize = 500;

    // Obtener todos los documentos
    let hasMore = true;
    let lastDoc = null;

    while (hasMore) {
        let query = collectionRef.limit(batchSize);
        
        // Si hay un último documento, empezar desde ahí (paginación)
        if (lastDoc) {
            query = query.startAfter(lastDoc);
        }

        const snapshot = await query.get();

        if (snapshot.empty) {
            hasMore = false;
            break;
        }

        // Eliminar cada documento y sus sub-colecciones
        const batch = db.batch();
        
        for (const doc of snapshot.docs) {
            // 1. Eliminar sub-colecciones del documento
            const subCollections = await doc.ref.listCollections();
            for (const subCol of subCollections) {
                const subColDeleted = await deleteCollection(subCol, `${collectionName}/${doc.id}/${subCol.id}`);
                totalDeleted += subColDeleted;
                console.log(`   🗑️  Eliminada sub-colección ${subCol.id} del documento ${doc.id} (${subColDeleted} documentos)`);
            }

            // 2. Eliminar el documento
            batch.delete(doc.ref);
            totalDeleted++;
            lastDoc = doc;
        }

        // Commit del batch
        await batch.commit();
        console.log(`   ✅ Procesados ${totalDeleted} documentos de ${collectionName}...`);

        // Si hay menos documentos que el batch size, terminamos
        if (snapshot.size < batchSize) {
            hasMore = false;
        }
    }

    return totalDeleted;
}

async function cleanDatabase() {
    try {
        console.log('\n' + '='.repeat(70));
        console.log('🧹 SCRIPT DE LIMPIEZA DE BASE DE DATOS');
        console.log('='.repeat(70));
        console.log('\n⚠️  ADVERTENCIA: Esta operación eliminará TODAS las colecciones');
        console.log('   EXCEPTO la colección "users" que será preservada completamente.');
        console.log('   Esta operación es IRREVERSIBLE!\n');

        // Pedir confirmación
        const confirm1 = await askConfirmation('¿Estás seguro de que quieres continuar? (escribe "SI" para confirmar): ');
        if (confirm1 !== 'si') {
            console.log('\n❌ Operación cancelada por el usuario.');
            process.exit(0);
        }

        const confirm2 = await askConfirmation('\n⚠️  Última confirmación. Escribe "ELIMINAR" para proceder: ');
        if (confirm2 !== 'eliminar') {
            console.log('\n❌ Operación cancelada por el usuario.');
            process.exit(0);
        }

        console.log('\n🚀 Iniciando limpieza de base de datos...\n');

        // 1. Obtener todas las colecciones
        const collections = await db.listCollections();
        const collectionNames = collections.map(col => col.id);

        console.log(`📋 Colecciones encontradas: ${collectionNames.join(', ')}\n`);

        // 2. Filtrar colecciones a eliminar (excluir 'users')
        const collectionsToDelete = collections.filter(col => col.id !== 'users');
        const collectionsToPreserve = collections.filter(col => col.id === 'users');

        if (collectionsToPreserve.length > 0) {
            console.log(`✅ Colección preservada: users`);
            const usersSnapshot = await db.collection('users').get();
            console.log(`   - Usuarios preservados: ${usersSnapshot.size}`);
            console.log(`   - Todos los créditos y datos de usuarios se mantienen intactos\n`);
        }

        if (collectionsToDelete.length === 0) {
            console.log('ℹ️  No hay colecciones para eliminar (solo existe "users").');
            process.exit(0);
        }

        console.log(`🗑️  Colecciones a eliminar: ${collectionsToDelete.map(c => c.id).join(', ')}\n`);

        const deletionResults = [];

        // 3. Eliminar cada colección y sus documentos (incluyendo sub-colecciones)
        for (const collectionRef of collectionsToDelete) {
            const collectionName = collectionRef.id;

            try {
                console.log(`🗑️  Eliminando colección: ${collectionName}`);

                const documentsDeleted = await deleteCollection(collectionRef, collectionName);

                deletionResults.push({
                    collection: collectionName,
                    documentsDeleted: documentsDeleted,
                    status: 'success'
                });

                console.log(`✅ Colección ${collectionName} eliminada completamente (${documentsDeleted} documentos incluyendo sub-colecciones)\n`);

            } catch (error) {
                console.error(`❌ Error eliminando colección ${collectionName}:`, error.message);
                deletionResults.push({
                    collection: collectionName,
                    documentsDeleted: 0,
                    status: 'error',
                    error: error.message
                });
            }
        }

        // 4. Resumen final
        const totalDeleted = deletionResults.reduce((sum, r) => sum + r.documentsDeleted, 0);
        const successful = deletionResults.filter(r => r.status === 'success').length;
        const errors = deletionResults.filter(r => r.status === 'error').length;

        console.log('\n' + '='.repeat(70));
        console.log('✅ LIMPIEZA COMPLETADA');
        console.log('='.repeat(70));
        console.log(`   📊 Colecciones procesadas: ${collectionsToDelete.length}`);
        console.log(`   ✅ Colecciones eliminadas exitosamente: ${successful}`);
        console.log(`   ❌ Errores: ${errors}`);
        console.log(`   🗑️  Total de documentos eliminados: ${totalDeleted}`);
        console.log(`   👥 Usuarios preservados: ${collectionsToPreserve.length > 0 ? 'Sí (colección "users" intacta)' : 'N/A'}`);
        console.log('='.repeat(70) + '\n');

        // Mostrar detalles
        if (deletionResults.length > 0) {
            console.log('📋 Detalles por colección:');
            deletionResults.forEach(result => {
                if (result.status === 'success') {
                    console.log(`   ✅ ${result.collection}: ${result.documentsDeleted} documentos eliminados`);
                } else {
                    console.log(`   ❌ ${result.collection}: Error - ${result.error}`);
                }
            });
            console.log('');
        }

        console.log('🎉 Script completado exitosamente!');
        console.log('💡 Puedes verificar los resultados en la consola de Firebase:');
        console.log('   https://console.firebase.google.com/project/poker-fa33a/firestore\n');

    } catch (error) {
        console.error('\n💥 Error fatal durante la limpieza:', error);
        console.error('⚠️  Algunos datos pueden haber sido eliminados. Revisa los detalles arriba.\n');
        process.exit(1);
    }
}

// Ejecutar el script
cleanDatabase()
    .then(() => {
        console.log('✨ Script finalizado correctamente');
        process.exit(0);
    })
    .catch((error) => {
        console.error('💥 El script falló:', error);
        process.exit(1);
    });

