import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';

class SocketService extends ChangeNotifier {
  late IO.Socket _socket;
  bool _isConnected = false;

  bool get isConnected => _isConnected;
  IO.Socket get socket => _socket;
  String? get socketId => _socket.id;

  Future<void> connect() async {
    // Adjust URL based on platform
    String uri = kIsWeb 
      ? 'https://poker-server-s8yj.onrender.com'  // Production backend (Render)
      : 'http://10.0.2.2:3000';  // Android emulator (local)
    
    // Get Firebase token
    final user = FirebaseAuth.instance.currentUser;
    String? token;
    if (user != null) {
      token = await user.getIdToken();
    }

    _socket = IO.io(uri, IO.OptionBuilder()
      .setTransports(['websocket'])
      .disableAutoConnect()
      .build());

    _socket.connect();

    _socket.onConnect((_) async {
      print('Connected to server');
      
      // Get fresh token on every connection
      final user = FirebaseAuth.instance.currentUser;
      String? freshToken;
      if (user != null) {
        freshToken = await user.getIdToken();
      }
      
      // Authenticate
      if (freshToken != null) {
        print('Sending authenticate event with token');
        _socket.emit('authenticate', {'token': freshToken});
      } else {
        print('No user logged in, skipping authentication');
      }

      _isConnected = true;
      notifyListeners();
    });

    _socket.onDisconnect((_) {
      print('Disconnected from server');
      _isConnected = false;
      notifyListeners();
    });

    _socket.onError((data) => print('Socket Error: $data'));
    
    _socket.on('insufficient_balance', (data) {
      print('Insufficient balance: ${data['required']} required, ${data['current']} available');
      // We can notify listeners or use a stream controller if we want the UI to react globally
      // For now, we'll let the specific room callbacks handle errors if they come as errors, 
      // but insufficient_balance is a specific event. 
      // Ideally, we should expose a stream or callback for this.
      // However, since createRoom/joinRoom have onError, we can also emit an error there if we want,
      // but the server emits 'insufficient_balance' separately.
      // Let's forward it as an error to the active listeners if possible, or just print for now 
      // and let the UI handle it via a global listener if we add one.
      // Actually, let's add a global stream for events like this.
      _socketEventStream.add({'type': 'insufficient_balance', 'data': data});
    });
  }

  // Add a stream controller for socket events
  final _socketEventStream = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get socketEventStream => _socketEventStream.stream;

  Future<void> createRoom(String playerName, {Function(String roomId)? onSuccess, Function(String error)? onError}) async {
    print('Emitting create_room event for $playerName');
    
    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken();

    _socket.emit('create_room', {
      'playerName': playerName,
      'token': token
    });
    
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

    _socket.once('insufficient_balance', (data) {
       if (onError != null) {
         onError('Insufficient balance. Required: ${data['required']}, Available: ${data['current']}');
       }
    });
  }

  Future<void> joinRoom(String roomId, String playerName, {Function(String roomId)? onSuccess, Function(String error)? onError}) async {
    print('Emitting join_room event for $playerName to room $roomId');
    
    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken();

    _socket.emit('join_room', {
      'roomId': roomId, 
      'playerName': playerName,
      'token': token
    });
    
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

    _socket.once('insufficient_balance', (data) {
       if (onError != null) {
         onError('Insufficient balance. Required: ${data['required']}, Available: ${data['current']}');
       }
    });
  }

  void createPracticeRoom(String playerName, {Function(dynamic data)? onSuccess, Function(String error)? onError}) {
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
    
    // Set up listeners first to avoid race conditions
    _socket.on('room_created', handleRoomCreated);
    _socket.on('game_started', handleGameStarted);
    _socket.on('error', handleError);

    print('Emitting create_practice_room event for $playerName');
    _socket.emit('create_practice_room', playerName);
    
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

