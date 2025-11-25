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

  void createPracticeRoom(String playerName, {Function(dynamic data)? onSuccess, Function(String error)? onError}) {
    print('Emitting create_practice_room event for $playerName');
    _socket.emit('create_practice_room', playerName);
    
    String? capturedRoomId;
    bool navigationCompleted = false;
    
    // Declare cleanup function first
    void cleanup() {
      _socket.off('room_created');
      _socket.off('game_started');
      _socket.off('error');
    }
    
    // Listen for room_created first (server emits this immediately)
    void handleRoomCreated(dynamic data) {
      if (navigationCompleted) return;
      print('Practice room created: ${data['id']}');
      capturedRoomId = data['id'];
    }
    
    // Error handler
    void handleError(dynamic data) {
      if (navigationCompleted) return;
      navigationCompleted = true;
      
      print('Practice room error: $data');
      cleanup();
      
      if (onError != null) {
        onError(data.toString());
      }
    }
    
    // Wait for game_started - server emits this when bots are ready and game begins
    void handleGameStarted(dynamic data) {
      if (navigationCompleted) return;
      navigationCompleted = true;
      
      print('Practice game started successfully with data: $data');
      final roomId = data['roomId'] ?? capturedRoomId;
      
      cleanup();
      
      if (roomId != null && onSuccess != null) {
        print('Navigating to practice game with roomId: $roomId');
        // Pass the full data object (gameState) to the callback
        onSuccess(data);
      } else {
        print('ERROR: No roomId found! data: $data, capturedRoomId: $capturedRoomId');
        if (onError != null) {
          onError('Failed to start practice game - no room ID');
        }
      }
    }
    
    // Set up listeners
    _socket.on('room_created', handleRoomCreated);
    _socket.on('game_started', handleGameStarted);
    _socket.on('error', handleError);
    
    // Timeout to show error if server doesn't respond (but don't navigate!)
    Future.delayed(const Duration(seconds: 10), () {
      if (!navigationCompleted) {
        navigationCompleted = true;
        cleanup();
        print('Practice game timeout - server did not respond');
        if (onError != null) {
          onError('Server took too long to start practice game. Please try again.');
        }
      }
    });
  }
}

