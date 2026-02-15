import 'package:flutter/foundation.dart';
import 'auth_service.dart';
import 'supabase_gate.dart';

class AccountDeletionService {
  AccountDeletionService._();
  static final AccountDeletionService instance = AccountDeletionService._();

  Future<void> requestDeletion() async {
    if (!SupabaseGate.isEnabled) {
      throw Exception('Supabase ist nicht aktiv.');
    }
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) {
      throw Exception('Kein Benutzer angemeldet.');
    }

    try {
      final supabase = SupabaseGate.client;
      await supabase.from('account_deletion_requests').insert({
        'user_id': currentUser.id,
        'email': currentUser.email,
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ AccountDeletionService: request failed: $e');
      }
      rethrow;
    }
  }
}



