import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';

class SocketService extends ChangeNotifier {
  IO.Socket? _socket;
  bool _isConnected = false;
  bool _isConnecting = false;
  DateTime? _lastConnectionAttempt;
  int _connectionAttempts = 0;
  static const int _maxConnectionAttempts = 3;
  static const Duration _minRetryDelay = Duration(seconds: 5);
  
  // Reconnection / Active Room State
  String? _currentRoomId;
  String? get currentRoomId => _currentRoomId;

  bool get isConnected => _isConnected && _socket != null;
  IO.Socket get socket {
    if (_socket == null) {
      throw Exception('Socket not initialized. Call connect() first.');
    }
    return _socket!;
  }
  String? get socketId => _socket?.id;

  Future<void> connect() async {
    // Prevent multiple simultaneous connection attempts
    if (_isConnecting) {
      print('Connection already in progress, skipping...');
      return;
    }

    // Check if already connected
    if (_isConnected && _socket != null && _socket!.connected) {
      print('Socket already connected');
      return;
    }

    // Rate limiting: Don't retry too quickly
    if (_lastConnectionAttempt != null) {
      final timeSinceLastAttempt = DateTime.now().difference(_lastConnectionAttempt!);
      if (timeSinceLastAttempt < _minRetryDelay) {
        print('Too soon to retry connection. Waiting...');
        return;
      }
    }

    // Check max attempts
    if (_connectionAttempts >= _maxConnectionAttempts) {
      print('Max connection attempts reached. Stopping retries.');
      return;
    }

    _isConnecting = true;
    _lastConnectionAttempt = DateTime.now();
    _connectionAttempts++;

    try {
      // Adjust URL based on platform
      String uri = kIsWeb 
        ? 'https://poker-server-s8yj.onrender.com'  // Production backend (Render)
        : 'http://10.0.2.2:3000';  // Android emulator (local)
      
      // Dispose existing socket if any
      _socket?.dispose();
      _socket?.disconnect();

      // Get Firebase token
      final user = FirebaseAuth.instance.currentUser;
      String? token;
      if (user != null) {
        token = await user.getIdToken();
      }

      _socket = IO.io(uri, IO.OptionBuilder()
        .setTransports(<String>['websocket'])
        .disableAutoConnect() // We handle connection manually to control retry logic
        .build());

      _socket!.connect();

      _socket!.onConnect((_) async {
        print('Connected to server');
        _isConnecting = false;
        _connectionAttempts = 0; // Reset on successful connection
        
        // Get fresh token on every connection
        final user = FirebaseAuth.instance.currentUser;
        String? freshToken;
        if (user != null) {
          freshToken = await user.getIdToken();
        }
        
        // Authenticate
        if (freshToken != null) {
          print('Sending authenticate event with token');
          _socket!.emit('authenticate', {'token': freshToken});
        } else {
          print('No user logged in, skipping authentication');
        }

        _isConnected = true;
        notifyListeners();
      });

      _socket!.onDisconnect((_) {
        print('Disconnected from server');
        _isConnected = false;
        _isConnecting = false;
        notifyListeners();
      });

      _socket!.onConnectError((error) {
        print('Socket connection error: $error');
        _isConnecting = false;
        _isConnected = false;
        notifyListeners();
        // Don't print repeatedly, only log once per attempt
      });

      // Only log errors once, not repeatedly
      bool errorLogged = false;
      _socket!.onError((data) {
        if (!errorLogged) {
          print('Socket Error: $data');
          errorLogged = true;
          // Reset flag after a delay to allow occasional error logging
          Future.delayed(const Duration(seconds: 10), () {
            errorLogged = false;
          });
        }
      });
    
      _socket!.on('insufficient_balance', (data) {
        print('Insufficient balance: ${data['required']} required, ${data['current']} available');
        _socketEventStream.add({'type': 'insufficient_balance', 'data': data});
      });
    } catch (e) {
      print('Error connecting socket: $e');
      _isConnecting = false;
      _isConnected = false;
      notifyListeners();
    }
  }

  /// Wait for socket connection to be established
  /// Returns true if connected, false if timeout or error
  Future<bool> waitForConnection({Duration timeout = const Duration(seconds: 10)}) async {
    if (_isConnected && _socket != null && _socket!.connected) {
      return true;
    }

    final completer = Completer<bool>();
    Timer? timeoutTimer;
    
    void checkConnection() {
      if (_isConnected && _socket != null && _socket!.connected) {
        timeoutTimer?.cancel();
        if (!completer.isCompleted) {
          completer.complete(true);
        }
      }
    }

    // Listen for connection state changes
    void listener() {
      checkConnection();
    }
    
    addListener(listener);
    
    // Check immediately in case already connected
    checkConnection();
    
    // Set timeout
    timeoutTimer = Timer(timeout, () {
      removeListener(listener);
      if (!completer.isCompleted) {
        print('Socket connection timeout after ${timeout.inSeconds} seconds');
        completer.complete(false);
      }
    });
    
    final result = await completer.future;
    removeListener(listener);
    timeoutTimer?.cancel();
    
    return result;
  }

  void disconnect() {
    _socket?.dispose();
    _socket?.disconnect();
    _socket = null;
    _isConnected = false;
    _isConnecting = false;
    _connectionAttempts = 0;
    _currentRoomId = null; // Clear room ID on disconnect
    notifyListeners();
  }

  // Add a stream controller for socket events
  final _socketEventStream = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get socketEventStream => _socketEventStream.stream;

  Future<void> createRoom(String playerName, {String? roomId, Function(String roomId)? onSuccess, Function(String error)? onError}) async {
    if (_socket == null || !_socket!.connected) {
      if (onError != null) {
        onError('Socket no conectado. Intenta nuevamente.');
      }
      return;
    }

    print('Emitting create_room event for $playerName${roomId != null ? ' with ID $roomId' : ''}');
    
    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken();

    _socket!.emit('create_room', {
      'playerName': playerName,
      'token': token,
      'roomId': roomId
    });
    
    // Set up one-time listeners for response
    _socket!.once('room_created', (data) {
      print('Room created successfully: ${data['id']}');
      
      // Track current room
      _currentRoomId = data['id'];
      notifyListeners();

      if (onSuccess != null) {
        onSuccess(data['id']);
      }
    });
    
    _socket!.once('error', (data) {
      print('Room creation error: $data');
      if (onError != null) {
        onError(data.toString());
      }
    });

    _socket!.once('insufficient_balance', (data) {
       if (onError != null) {
         onError('Insufficient balance. Required: ${data['required']}, Available: ${data['current']}');
       }
    });
  }

  Future<void> joinSpectator(String roomId, {Function(String roomId)? onSuccess, Function(String error)? onError}) async {
    if (_socket == null || !_socket!.connected) {
      if (onError != null) {
        onError('Socket no conectado. Intenta nuevamente.');
      }
      return;
    }

    print('Emitting join_spectator event for room $roomId');
    
    _socket!.emit('join_spectator', {'roomId': roomId});
    
    // Set up one-time listeners for response
    void handleSpectatorJoined(data) {
      print('Spectator joined room successfully: ${data['id']}');

      // Track current room
      _currentRoomId = data['id'];
      notifyListeners();

      if (onSuccess != null) {
        onSuccess(data['id']);
      }
      _socket!.off('spectator_joined', handleSpectatorJoined); // Cleanup
      _socket!.off('room_joined', handleSpectatorJoined); // Cleanup
    }

    // Listen for BOTH room_joined and spectator_joined
    _socket!.once('room_joined', handleSpectatorJoined);
    _socket!.once('spectator_joined', handleSpectatorJoined);
    
    _socket!.once('error', (data) {
      print('Spectator join error: $data');
      if (onError != null) {
        onError(data.toString());
      }
    });
  }

  Future<void> joinRoom(String roomId, String playerName, {bool isSpectator = false, Function(String roomId)? onSuccess, Function(String error)? onError}) async {
    if (_socket == null || !_socket!.connected) {
      if (onError != null) {
        onError('Socket no conectado. Intenta nuevamente.');
      }
      return;
    }

    print('Emitting join_room event for $playerName to room $roomId (isSpectator: $isSpectator)');
    
    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken();

    _socket!.emit('join_room', {
      'roomId': roomId, 
      'playerName': playerName,
      'token': token,
      'isSpectator': isSpectator
    });
    
    // Set up one-time listeners for response
    _socket!.once('room_joined', (data) {
      print('Room joined successfully: ${data['id']}');

      // Track current room
      _currentRoomId = data['id'];
      notifyListeners();

      if (onSuccess != null) {
        onSuccess(data['id']);
      }
    });
    
    _socket!.once('error', (data) {
      print('Room join error: $data');
      if (onError != null) {
        onError(data.toString());
      }
    });

    _socket!.once('insufficient_balance', (data) {
       if (onError != null) {
         onError('Insufficient balance. Required: ${data['required']}, Available: ${data['current']}');
       }
    });
  }
  
  // Method to clear room state manually (e.g. when properly leaving via UI)
  void clearCurrentRoom() {
    _currentRoomId = null;
    notifyListeners();
  }

  void createPracticeRoom(String playerName, {Function(dynamic data)? onSuccess, Function(String error)? onError}) {
    if (_socket == null || !_socket!.connected) {
      if (onError != null) {
        onError('Socket no conectado. Intenta nuevamente.');
      }
      return;
    }

    String? capturedRoomId;
    bool navigationCompleted = false;
    
    // Declare cleanup function first
    void cleanup() {
      _socket!.off('room_created');
      _socket!.off('game_started');
      _socket!.off('error');
    }
    
    // Listen for room_created first (server emits this immediately)
    void handleRoomCreated(dynamic data) {
      if (navigationCompleted) return;
      print('Practice room created: ${data['id']}');
      capturedRoomId = data['id'];
      
      // Track practice room too
      _currentRoomId = capturedRoomId;
      notifyListeners();
    }
    
    // Error handler
    void handleError(dynamic data) {
      if (navigationCompleted) return;
      navigationCompleted = true;
      
      print('Practice room error: $data');
      cleanup();
      
      // Reset room if failed
      _currentRoomId = null;
      notifyListeners();

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
    _socket!.on('room_created', handleRoomCreated);
    _socket!.on('game_started', handleGameStarted);
    _socket!.on('error', handleError);

    print('Emitting create_practice_room event for $playerName');
    _socket!.emit('create_practice_room', playerName);
    
    // Timeout to show error if server doesn't respond (but don't navigate!)
    Future.delayed(const Duration(seconds: 10), () {
      if (!navigationCompleted) {
        navigationCompleted = true;
        cleanup();
        
        _currentRoomId = null; // Clear on timeout
        notifyListeners();
        
        print('Practice game timeout - server did not respond');
        if (onError != null) {
          onError('Server took too long to start practice game. Please try again.');
        }
      }
    });
  }

  Future<void> topUp(String roomId, double amount, {Function(double amount)? onSuccess, Function(String error)? onError}) async {
    if (_socket == null || !_socket!.connected) {
      if (onError != null) {
        onError('Socket no conectado. Intenta nuevamente.');
      }
      return;
    }

    print('Emitting request_top_up event for room $roomId with amount $amount');
    
    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken();

    _socket!.emit('request_top_up', {
      'roomId': roomId,
      'amount': amount,
      'token': token
    });
    
    _socket!.once('top_up_success', (data) {
      print('Top up successful: ${data['amount']}');
      if (onSuccess != null) {
        onSuccess((data['amount'] as num).toDouble());
      }
    });
    
    _socket!.once('error', (data) {
      print('Top up error: $data');
      if (onError != null) {
        // Handle both simple string errors and object errors
        String errorMessage = data.toString();
        if (data is Map && data.containsKey('message')) {
          errorMessage = data['message'];
        }
        onError(errorMessage);
      }
    });
  }

  void closeRoom(String roomId) {
    if (_socket != null && _socket!.connected) {
      print('Emitting close_room for $roomId');
      _socket!.emit('close_room', {'roomId': roomId});
    }
  }
}
