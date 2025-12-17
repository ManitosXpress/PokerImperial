// ---------------------------------------------------------------------------
// INSTRUCCIONES PARA EL CLIENTE FLUTTER (GameTableScreen / Controller)
// ---------------------------------------------------------------------------

// 1. Escuchar el evento 'hand_winner' del socket
socket.on('hand_winner', (data) async {
  print('🏆 Hand Winner Event Received: $data');
  
  // 2. Extraer datos de seguridad del payload
  // IMPORTANTE: No modificar authPayload ni securitySignature
  final String? authPayload = data['authPayload'];
  final String? securitySignature = data['securitySignature'];
  
  // 3. Identificar si soy el ganador (para detonar la liquidación)
  // Solo el ganador (o todos, pero el backend debe ser idempotente) debería llamar a la función.
  // Para mayor seguridad y redundancia, el ganador es el responsable principal.
  final String myUid = AuthService.instance.currentUser?.uid ?? '';
  
  // Verificar si soy uno de los ganadores
  bool amIWinner = false;
  if (data['winners'] != null) {
    for (var winner in data['winners']) {
      if (winner['id'] == myUid) { // Asumiendo que id es el uid, o verificar mapeo
        amIWinner = true;
        break;
      }
    }
  } else if (data['winner'] != null) {
    if (data['winner']['uid'] == myUid) {
      amIWinner = true;
    }
  }

  // 4. Llamar a Cloud Function para liquidar la mano
  if (amIWinner && authPayload != null && securitySignature != null) {
    print('🔐 Secure Handoff: Triggering settleGameRound...');
    
    try {
      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('settleGameRoundFunction');
      
      await callable.call({
        'tableId': widget.tableId, // ID de la mesa actual
        'gameId': data['gameState']['gameId'] ?? 'unknown_game', // O generar uno si no viene
        'winnerUid': myUid,
        'potTotal': data['gameState']['pot'] ?? 0, // O calcular del payload
        'finalPlayerStacks': _extractStacks(data['players']), // Helper para extraer stacks actuales
        
        // 🔐 CAMPOS CRÍTICOS DE SEGURIDAD
        'authPayload': authPayload,
        'signature': securitySignature,
      });
      
      print('✅ Hand settled successfully on backend');
    } catch (e) {
      print('❌ Error settling hand: $e');
      // Opcional: Reintentar o notificar error
    }
  }
});

// Helper para extraer stacks en formato {uid: chips}
Map<String, int> _extractStacks(List<dynamic> players) {
  Map<String, int> stacks = {};
  for (var p in players) {
    if (p['uid'] != null) {
      stacks[p['uid']] = p['chips'];
    }
  }
  return stacks;
}
