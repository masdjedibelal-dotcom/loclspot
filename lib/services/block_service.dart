import 'package:flutter/foundation.dart';
import 'auth_service.dart';
import 'supabase_gate.dart';

class BlockService {
  BlockService._internal();
  static final BlockService instance = BlockService._internal();

  final Set<String> _blockedIds = {};
  Future<Set<String>>? _loadFuture;

  bool isBlockedSync(String userId) => _blockedIds.contains(userId);

  Future<bool> isBlocked(String userId) async {
    await getBlockedUserIds();
    return _blockedIds.contains(userId);
  }

  Future<Set<String>> getBlockedUserIds({bool force = false}) async {
    if (!SupabaseGate.isEnabled) {
      _blockedIds.clear();
      return _blockedIds;
    }
    if (!force && _loadFuture != null) {
      return _loadFuture!;
    }
    _loadFuture = _loadBlockedIds();
    return _loadFuture!;
  }

  Future<void> refresh() async {
    await getBlockedUserIds(force: true);
  }

  void clear() {
    _blockedIds.clear();
    _loadFuture = null;
  }

  Future<void> blockUser(String userId) async {
    if (!SupabaseGate.isEnabled) {
      throw Exception('Supabase ist nicht konfiguriert.');
    }
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) {
      throw Exception('Bitte zuerst einloggen.');
    }
    if (currentUser.id == userId) {
      throw Exception('Du kannst dich nicht selbst blockieren.');
    }
    final supabase = SupabaseGate.client;
    await supabase.from('blocks').upsert(
      {
        'blocker_id': currentUser.id,
        'blocked_id': userId,
      },
      onConflict: 'blocker_id,blocked_id',
    );
    _blockedIds.add(userId);
  }

  Future<void> unblockUser(String userId) async {
    if (!SupabaseGate.isEnabled) {
      throw Exception('Supabase ist nicht konfiguriert.');
    }
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) {
      throw Exception('Bitte zuerst einloggen.');
    }
    final supabase = SupabaseGate.client;
    await supabase
        .from('blocks')
        .delete()
        .eq('blocker_id', currentUser.id)
        .eq('blocked_id', userId);
    _blockedIds.remove(userId);
  }

  Future<Set<String>> _loadBlockedIds() async {
    if (!SupabaseGate.isEnabled) {
      _blockedIds.clear();
      return _blockedIds;
    }
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) {
      _blockedIds.clear();
      return _blockedIds;
    }
    try {
      final supabase = SupabaseGate.client;
      final response = await supabase
          .from('blocks')
          .select('blocked_id')
          .eq('blocker_id', currentUser.id);
      _blockedIds
        ..clear()
        ..addAll(
          (response as List)
              .map((row) => row['blocked_id'] as String?)
              .whereType<String>(),
        );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ BlockService: Failed to load blocked ids: $e');
      }
    }
    return _blockedIds;
  }
}

