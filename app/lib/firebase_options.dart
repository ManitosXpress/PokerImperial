// IMPORTANTE: Este archivo debe ser generado con 'flutterfire configure'
// Este es un template - reemplázalo con tu configuración real

// Para generar este archivo correctamente:
// 1. Instala FlutterFire CLI: dart pub global activate flutterfire_cli
// 2. Ejecuta: flutterfire configure
// 3. Selecciona tu proyecto Firebase: poker-fa33a
// 4. Selecciona las plataformas que necesitas (Web, Android, iOS)

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAIdivcVKIWJY_8f3tl2VIDWd2Q-Wfg9zM',
    appId: '1:790242418126:web:58351530f85c60bf109f9f',
    messagingSenderId: '790242418126',
    projectId: 'poker-fa33a',
    authDomain: 'poker-fa33a.firebaseapp.com',
    storageBucket: 'poker-fa33a.firebasestorage.app',
    measurementId: 'G-71K9HPFMJV',
  );

  // REEMPLAZA ESTOS VALORES CON LOS DE TU PROYECTO

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBktS5PxvHBhWeQXy2Li12aOzgw-aLEF8c',
    appId: '1:790242418126:android:4c9cc0a214c44672109f9f',
    messagingSenderId: '790242418126',
    projectId: 'poker-fa33a',
    storageBucket: 'poker-fa33a.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAmjkIANx0QaEWXCu2sH2xNOSctpFSALCs',
    appId: '1:790242418126:ios:bab3aad38cd1eef6109f9f',
    messagingSenderId: '790242418126',
    projectId: 'poker-fa33a',
    storageBucket: 'poker-fa33a.firebasestorage.app',
    iosBundleId: 'com.poker.game.app',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyAmjkIANx0QaEWXCu2sH2xNOSctpFSALCs',
    appId: '1:790242418126:ios:bab3aad38cd1eef6109f9f',
    messagingSenderId: '790242418126',
    projectId: 'poker-fa33a',
    storageBucket: 'poker-fa33a.firebasestorage.app',
    iosBundleId: 'com.poker.game.app',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyAIdivcVKIWJY_8f3tl2VIDWd2Q-Wfg9zM',
    appId: '1:790242418126:web:b13b4ffd7b38e015109f9f',
    messagingSenderId: '790242418126',
    projectId: 'poker-fa33a',
    authDomain: 'poker-fa33a.firebaseapp.com',
    storageBucket: 'poker-fa33a.firebasestorage.app',
    measurementId: 'G-MVNCYHPERC',
  );

}