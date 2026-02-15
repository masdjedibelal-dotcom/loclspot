import 'package:flutter/foundation.dart';
import 'auth_service.dart';
import 'supabase_gate.dart';

class ModerationService {
  ModerationService._();
  static final ModerationService instance = ModerationService._();

  Set<String>? _blockedCache;

  Future<Set<String>> getBlockedUserIds({bool refresh = false}) async {
    if (!SupabaseGate.isEnabled) {
      return {};
    }
    if (!refresh && _blockedCache != null) {
      return _blockedCache!;
    }
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) {
      _blockedCache = {};
      return _blockedCache!;
    }
    try {
      final supabase = SupabaseGate.client;
      final response = await supabase
          .from('user_blocks')
          .select('blocked_user_id')
          .eq('blocker_id', currentUser.id);
      final rows = (response as List?) ?? [];
      _blockedCache = rows
          .map((row) => row['blocked_user_id']?.toString())
          .whereType<String>()
          .toSet();
      return _blockedCache!;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ ModerationService: fetch blocked users failed: $e');
      }
      return _blockedCache ?? {};
    }
  }

  Future<void> blockUser({
    required String blockedUserId,
    String? reason,
    String? contextType,
    String? contextId,
  }) async {
    if (!SupabaseGate.isEnabled) {
      return;
    }
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) {
      return;
    }
    try {
      final supabase = SupabaseGate.client;
      await supabase.from('user_blocks').insert({
        'blocker_id': currentUser.id,
        'blocked_user_id': blockedUserId,
        'reason': reason,
      });
      _blockedCache = null;
      await reportContent(
        contentType: contextType ?? 'user',
        contentId: contextId ?? blockedUserId,
        reason: reason ?? 'blocked',
        details: 'blocked_user_id=$blockedUserId',
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ ModerationService: block user failed: $e');
      }
      rethrow;
    }
  }

  Future<void> reportContent({
    required String contentType,
    required String contentId,
    required String reason,
    String? details,
  }) async {
    if (!SupabaseGate.isEnabled) {
      return;
    }
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) {
      return;
    }
    try {
      final supabase = SupabaseGate.client;
      await supabase.from('content_reports').insert({
        'reporter_id': currentUser.id,
        'content_type': contentType,
        'content_id': contentId,
        'reason': reason,
        'details': details,
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ ModerationService: report content failed: $e');
      }
      rethrow;
    }
  }
}



