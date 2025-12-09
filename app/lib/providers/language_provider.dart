import 'package:flutter/material.dart';

class LanguageProvider with ChangeNotifier {
  Locale _currentLocale = const Locale('es'); // Default to Spanish as requested implicitly by user context

  Locale get currentLocale => _currentLocale;

  void toggleLanguage() {
    _currentLocale = _currentLocale.languageCode == 'en' 
        ? const Locale('es') 
        : const Locale('en');
    notifyListeners();
  }

  String getText(String key) {
    return _localizedValues[_currentLocale.languageCode]?[key] ?? key;
  }

  // Poker hand translation
  String translateHand(String englishHand) {
    if (_currentLocale.languageCode == 'en') return englishHand;

    String result = englishHand;
    _pokerTerms.forEach((english, spanish) {
      result = result.replaceAll(english, spanish);
    });
    return result;
  }

  static final Map<String, String> _pokerTerms = {
    'High Card': 'Carta Alta',
    'Pair': 'Par',
    'Two Pair': 'Doble Par',
    'Three of a Kind': 'Trío',
    'Straight': 'Escalera',
    'Flush': 'Color',
    'Full House': 'Full',
    'Four of a Kind': 'Poker',
    'Straight Flush': 'Escalera de Color',
    'Royal Flush': 'Escalera Real',
    'Ace': 'As',
    'King': 'Rey',
    'Queen': 'Reina',
    'Jack': 'Jota',
    '\'s': '',
    'high': 'alta',
  };

  static final Map<String, Map<String, String>> _localizedValues = {
    'en': {
      'app_title': 'POKER IMPERIAL',
      'play_now': 'PLAY NOW',
      'create_room': 'CREATE ROOM',
      'practice_bots': 'PRACTICE WITH BOTS',
      'join_room': 'JOIN ROOM',
      'your_name': 'Your Name',
      'room_id': 'Room ID',
      'join': 'JOIN',
      'connecting': 'Connecting to server...',
      'connected': 'Connected',
      'room_created': '🎉 Room Created',
      'share_code': 'Share this code with friends:',
      'copy_code': 'Copy Code',
      'copied': '✅ Code copied to clipboard',
      'go_to_room': 'Go to Room',
      'waiting_players': 'Waiting for players...',
      'players': 'Players',
      'start_game': 'START GAME',
      'need_players': 'Need at least 2 players',
      'check': 'Check',
      'call': 'Call',
      'fold': 'Fold',
      'raise': 'Raise',
      'all_in': 'ALL-IN',
      'custom_bet': 'Custom Bet',
      'enter_amount': 'Enter amount',
      'min': 'Min',
      'max': 'Max',
      'winner': 'WINNER!',
      'loser': 'YOU LOST!',
      'tie': 'TIE!',
      'wins': 'wins',
      'next_hand': 'Next hand shortly...',
      'exit': 'Exit',
      'continue': 'Continue',
      'player_cards': 'Player Cards:',
      'pot': 'Pot',
      'community_cards': 'Community Cards',
      'waiting_turn': 'Waiting for turn...',
      'your_turn': 'YOUR TURN',
      'profile': 'PROFILE',
      'my_profile': 'My Profile',
      'wallet': 'Wallet',
      'balance': 'Balance',
      'transactions': 'Transaction History',
      'no_transactions': 'No transactions yet',
      'edit_profile': 'Edit Profile',
      'display_name': 'Display Name',
      'save': 'Save',
      'cancel': 'Cancel',
      'sign_out': 'Sign Out',
      'credit': 'Credit',
      'debit': 'Debit',
      'club_request': 'CLUB REQUEST',
      'business_model': 'BUSINESS MODEL',
      'apply': 'UNDERSTOOD, I WANT TO APPLY',
      'request_via_telegram': 'REQUEST ON TELEGRAM',
      'opening_telegram': 'OPENING TELEGRAM...',
      'club_name': 'Club Name',
      'short_desc': 'Short Description',
      'logo_url': 'Image/Logo Link (Optional)',
      'initial_credits': 'Initial Credits to Buy',
      'confirmation_text': 'In a few minutes, all data for your club creation will be checked.',
      'follow_steps': 'Follow the steps indicated on Telegram. And when all data is ready, your club profile will automatically appear.',
      'accept': 'Accept',
      'return_conditions': 'Return to read conditions',
    },
    'es': {
      'app_title': 'POKER IMPERIAL',
      'play_now': 'JUEGA YA',
      'create_room': 'CREAR SALA',
      'practice_bots': 'PRACTICAR CON BOTS',
      'join_room': 'UNIRSE A SALA',
      'your_name': 'Tu Nombre',
      'room_id': 'ID de Sala',
      'join': 'ENTRAR',
      'connecting': 'Conectando al servidor...',
      'connected': 'Conectado',
      'room_created': '🎉 Sala Creada',
      'share_code': 'Comparte este código con amigos:',
      'copy_code': 'Copiar Código',
      'copied': '✅ Código copiado al portapapeles',
      'go_to_room': 'Ir a la Sala',
      'waiting_players': 'Esperando jugadores...',
      'players': 'Jugadores',
      'start_game': 'INICIAR JUEGO',
      'need_players': 'Se necesitan al menos 2 jugadores',
      'check': 'Pasar',
      'call': 'Igualar',
      'fold': 'Retirarse',
      'raise': 'Subir',
      'all_in': 'TODO INCLUIDO',
      'custom_bet': 'Apuesta Personalizada',
      'enter_amount': 'Ingrese monto',
      'min': 'Mín',
      'max': 'Máx',
      'winner': '¡GANASTE!',
      'loser': '¡PERDISTE!',
      'tie': '¡EMPATE!',
      'wins': 'gana',
      'next_hand': 'Próxima mano en breve...',
      'exit': 'Salir',
      'continue': 'Continuar',
      'player_cards': 'Cartas de los Jugadores:',
      'pot': 'Bote',
      'community_cards': 'Cartas Comunitarias',
      'waiting_turn': 'Esperando turno...',
      'your_turn': 'TU TURNO',
      'profile': 'PERFIL',
      'my_profile': 'Mi Perfil',
      'wallet': 'Billetera',
      'balance': 'Saldo',
      'transactions': 'Historial de Transacciones',
      'no_transactions': 'No hay transacciones aún',
      'edit_profile': 'Editar Perfil',
      'display_name': 'Nombre para Mostrar',
      'save': 'Guardar',
      'cancel': 'Cancelar',
      'sign_out': 'Cerrar Sesión',
      'credit': 'Crédito',
      'debit': 'Débito',
      'club_request': 'SOLICITUD DE CLUB',
      'business_model': 'MODELO DE NEGOCIO',
      'apply': 'ENTENDIDO, QUIERO APLICAR',
      'request_via_telegram': 'SOLICITAR EN TELEGRAM',
      'opening_telegram': 'ABRIENDO TELEGRAM...',
      'club_name': 'Nombre del Club',
      'short_desc': 'Descripción Corta',
      'logo_url': 'Link de Imagen/Logo (Opcional)',
      'initial_credits': 'Créditos Iniciales a Comprar',
      'confirmation_text': 'En unos minutos se comprobaran todos los datos para la creacion de su club.',
      'follow_steps': 'Siga los pasos que se le indiquen en Telegram. Y cuando todos los datos esten listos, aparecera automaticamente el perfil de su club.',
      'accept': 'Aceptar',
      'return_conditions': 'Volver a leer condiciones',
    },
  };
}
