// Ejecuta este script desde la consola del navegador (F12 > Console)
// Pega este código y presiona Enter

firebase.firestore().collection('live_feed').add({
    type: 'big_win',
    playerName: 'Juan Pérez',
    amount: 5000,
    tableId: 'cash_table_001',
    timestamp: firebase.firestore.FieldValue.serverTimestamp()
}).then(() => {
    console.log('✅ Evento creado! El ticker debería aparecer ahora.');
}).catch((error) => {
    console.error('❌ Error:', error.message);
});
