import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';
import '../models/app_user.dart';
import 'supabase_gate.dart';

/// Service for managing authentication state
class AuthService extends ChangeNotifier {
  static AuthService? _instance;
  
  /// Singleton instance
  static AuthService get instance {
    _instance ??= AuthService._();
    return _instance!;
  }
  
  AppUser? _currentUser;

  /// Current authenticated user, null if not logged in
  AppUser? get currentUser => _currentUser;

  /// ValueNotifier for reactive updates
  final ValueNotifier<AppUser?> currentUserNotifier = ValueNotifier<AppUser?>(null);

  AuthService._() {
    // Initialize with null user
    _currentUser = null;
    currentUserNotifier.value = null;

    // Listen to Supabase auth state changes only if enabled
    if (SupabaseGate.isEnabled) {
      try {
        final supabase = SupabaseGate.client;
        supabase.auth.onAuthStateChange.listen((data) {
          _updateUserFromSession(data.session);
        });

        // Check for existing session on initialization (safe for refresh)
        final existingSession = supabase.auth.currentSession;
        _updateUserFromSession(existingSession);
      } catch (e) {
        // Defensive: if Supabase access fails, continue in demo mode
        if (kDebugMode) {
          debugPrint('⚠️ AuthService: Failed to initialize Supabase auth listener: $e');
        }
      }
    }
  }

  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)])
        .join();
  }

  String _sha256ofString(String input) {
    return sha256.convert(utf8.encode(input)).toString();
  }

  /// Update current user from Supabase session
  void _updateUserFromSession(Session? session) {
    final wasLoggedIn = _currentUser != null;
    
    if (session?.user == null) {
      if (wasLoggedIn && kDebugMode) {
        debugPrint('🔴 AuthService: User signed out');
      }
      _currentUser = null;
      currentUserNotifier.value = null;
    } else {
      final user = session!.user;
      final userMetadata = user.userMetadata ?? {};

      // Extract user info from Supabase user
      // Supabase stores Google profile in user_metadata
      final name = userMetadata['full_name'] as String? ??
          userMetadata['name'] as String? ??
          (user.email != null ? user.email!.split('@').first : 'User');
      
      final email = user.email;
      final photoUrl = userMetadata['avatar_url'] as String? ??
          userMetadata['picture'] as String?;

      final newUser = AppUser(
        id: user.id,
        name: name,
        email: email,
        photoUrl: photoUrl,
      );
      
      // Only log if state actually changed
      if (!wasLoggedIn || _currentUser?.id != newUser.id) {
        if (kDebugMode) {
          debugPrint('🟢 AuthService: User signed in (${newUser.name}, ${newUser.email ?? 'no email'})');
        }
      }
      
      _currentUser = newUser;
      currentUserNotifier.value = _currentUser;
    }
    notifyListeners();
  }

  /// Sign in with Apple OAuth (required by App Review when other 3rd-party login is present)
  Future<void> signInWithApple() async {
    if (!SupabaseGate.isEnabled) {
      if (kDebugMode) {
        debugPrint('⚠️ AuthService: Apple login attempted but Supabase is not enabled');
      }
      throw Exception('Supabase ist noch nicht konfiguriert.');
    }

    try {
      if (kDebugMode) {
        debugPrint('🔄 AuthService: Initiating Apple OAuth sign-in...');
      }
      final supabase = SupabaseGate.client;
      if (Platform.isIOS) {
        if (!await SignInWithApple.isAvailable()) {
          throw Exception('Apple Login ist auf diesem Gerät nicht verfügbar.');
        }

        final rawNonce = _generateNonce();
        final hashedNonce = _sha256ofString(rawNonce);

        final credential = await SignInWithApple.getAppleIDCredential(
          scopes: [
            AppleIDAuthorizationScopes.email,
            AppleIDAuthorizationScopes.fullName,
          ],
          nonce: hashedNonce,
        );

        final identityToken = credential.identityToken;
        if (identityToken == null || identityToken.isEmpty) {
          throw Exception('Kein Apple ID Token erhalten.');
        }

        await supabase.auth.signInWithIdToken(
          provider: OAuthProvider.apple,
          idToken: identityToken,
          nonce: rawNonce,
        );
      } else {
        await supabase.auth.signInWithOAuth(
          OAuthProvider.apple,
          redirectTo: kIsWeb ? Uri.base.origin : AppConfig.oauthRedirectUri,
          authScreenLaunchMode: LaunchMode.inAppBrowserView,
        );
      }
      if (kDebugMode) {
        debugPrint('✅ AuthService: Apple OAuth sign-in initiated successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ AuthService: Apple OAuth sign-in failed: $e');
      }
      throw Exception('Failed to sign in with Apple: $e');
    }
  }

  /// Sign out the current user
  /// Works for both Supabase users and demo users
  Future<void> signOut() async {
    // If Supabase is enabled and user is logged in via Supabase, sign out from Supabase
    if (SupabaseGate.isEnabled && _currentUser != null) {
      try {
        if (kDebugMode) {
          debugPrint('🔄 AuthService: Signing out from Supabase...');
        }
        final supabase = SupabaseGate.client;
        await supabase.auth.signOut();
        if (kDebugMode) {
          debugPrint('✅ AuthService: Supabase sign-out successful');
        }
      } catch (e) {
        // Continue with local sign out even if Supabase sign out fails
        if (kDebugMode) {
          debugPrint('⚠️ AuthService: Supabase sign-out failed, continuing with local sign-out: $e');
        }
      }
    }

    // Always clear local user state (works for both Supabase and demo users)
    if (kDebugMode && _currentUser != null) {
      debugPrint('🔴 AuthService: Clearing local user state');
    }
    _currentUser = null;
    currentUserNotifier.value = null;
    notifyListeners();
  }

  /// Sign in with a mock/demo user (for fallback/demo purposes)
  /// 
  /// Behavior:
  /// - If SupabaseGate is enabled: Uses Supabase signInWithPassword with demo credentials
  /// - If SupabaseGate is disabled: Creates local demo user with static UUID
  /// 
  /// For Supabase mode:
  /// - Email: "demo@mingalive.app"
  /// - Password: Read from --dart-define DEMO_PASSWORD (or placeholder if not set)
  /// 
  /// IMPORTANT: Create the demo user in Supabase Dashboard:
  /// 1. Go to Authentication > Users
  /// 2. Add user with email: demo@mingalive.app
  /// 3. Set password (must match DEMO_PASSWORD or placeholder)
  Future<void> signInMock() async {
    if (kDebugMode) {
      debugPrint('🟡 AuthService: Signing in with demo user');
    }

    if (SupabaseGate.isEnabled) {
      // Use Supabase authentication
      try {
        const demoEmail = 'demo@mingalive.app';
        // TODO: Replace with actual password from --dart-define DEMO_PASSWORD
        // Read password from environment variable or use placeholder
        const demoPassword = String.fromEnvironment(
          'DEMO_PASSWORD',
          defaultValue: 'demo_password_placeholder_change_me', // TODO: Set via --dart-define
        );

        if (kDebugMode) {
          if (demoPassword == 'demo_password_placeholder_change_me') {
            debugPrint('⚠️ AuthService: Using placeholder password. Set --dart-define=DEMO_PASSWORD=your_password');
          }
        }

        final supabase = SupabaseGate.client;
        final response = await supabase.auth.signInWithPassword(
          email: demoEmail,
          password: demoPassword,
        );

        // User will be updated via onAuthStateChange listener
        // But we can also update immediately from the response
        if (response.session != null) {
          _updateUserFromSession(response.session);
        }

        if (kDebugMode) {
          debugPrint('✅ AuthService: Demo user signed in via Supabase');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('❌ AuthService: Demo login failed: $e');
        }
        rethrow;
      }
    } else {
      // Local demo user (fallback when Supabase is disabled)
      _currentUser = const AppUser(
        id: '00000000-0000-0000-0000-000000000001', // Valid UUID for Supabase compatibility
        name: 'Demo User',
        email: 'demo@mingalive.app',
        photoUrl: null,
      );
      currentUserNotifier.value = _currentUser;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    currentUserNotifier.dispose();
    super.dispose();
  }
}

