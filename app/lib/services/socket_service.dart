import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter/foundation.dart';

class SocketService extends ChangeNotifier {
  late IO.Socket _socket;
  bool _isConnected = false;

  bool get isConnected => _isConnected;
  IO.Socket get socket => _socket;
  String? get socketId => _socket.id;

  void connect() {
    // Adjust URL based on platform
    String uri = kIsWeb 
      ? 'https://pokerimperial-production.up.railway.app'  // Production backend
      : 'http://10.0.2.2:3000';  // Android emulator (local)
    
    _socket = IO.io(uri, IO.OptionBuilder()
      .setTransports(['websocket'])
      .disableAutoConnect()
      .build());

    _socket.connect();

    _socket.onConnect((_) {
      print('Connected to server');
      _isConnected = true;
      notifyListeners();
    });

    _socket.onDisconnect((_) {
      print('Disconnected from server');
      _isConnected = false;
      notifyListeners();
    });

    _socket.onError((data) => print('Socket Error: $data'));
  }

  void createRoom(String playerName, {Function(String roomId)? onSuccess, Function(String error)? onError}) {
    print('Emitting create_room event for $playerName');
    _socket.emit('create_room', playerName);
    
    // Set up one-time listeners for response
    _socket.once('room_created', (data) {
      print('Room created successfully: ${data['id']}');
      if (onSuccess != null) {
        onSuccess(data['id']);
      }
    });
    
    _socket.once('error', (data) {
      print('Room creation error: $data');
      if (onError != null) {
        onError(data.toString());
      }
    });
  }

  void joinRoom(String roomId, String playerName, {Function(String roomId)? onSuccess, Function(String error)? onError}) {
    print('Emitting join_room event for $playerName to room $roomId');
    _socket.emit('join_room', {'roomId': roomId, 'playerName': playerName});
    
    // Set up one-time listeners for response
    _socket.once('room_joined', (data) {
      print('Room joined successfully: ${data['id']}');
      if (onSuccess != null) {
        onSuccess(data['id']);
      }
    });
    
    _socket.once('error', (data) {
      print('Room join error: $data');
      if (onError != null) {
        onError(data.toString());
      }
    });
  }

  void createPracticeRoom(String playerName, {Function(String roomId)? onSuccess}) {
    print('Emitting create_practice_room event for $playerName');
    _socket.emit('create_practice_room', playerName);
    
    // For practice rooms, wait for game_started event (not room_created)
    // This ensures we skip the waiting screen and go directly to the game
    _socket.once('game_started', (data) {
      print('Practice game started successfully');
      if (onSuccess != null && data['roomId'] != null) {
        onSuccess(data['roomId']);
      }
    });
  }
}
