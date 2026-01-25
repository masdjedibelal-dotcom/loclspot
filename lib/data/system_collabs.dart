import '../models/collab.dart';
import 'collabs.dart';
import '../services/supabase_gate.dart';

const String eventsThisWeekCollabId = 'events_this_week';
const String eventsTodayCollabId = 'events_today';
const String eventsHighlightsYearCollabId = 'events_highlights_year';
const List<String> eventSystemCollabIds = [
  eventsTodayCollabId,
  eventsThisWeekCollabId,
  eventsHighlightsYearCollabId,
];

const CollabDefinition _eventsThisWeekCollab = CollabDefinition(
  id: eventsThisWeekCollabId,
  title: 'Events',
  subtitle: 'Highlights der Woche',
  creatorId: 'localspots',
  creatorName: 'LocalSpots',
  creatorAvatarUrl: null,
  heroType: 'gradient',
  gradientKey: 'deep',
  query: CollabQuery(),
  limit: 30,
  requiresRuntime: false,
);

const CollabDefinition _eventsTodayCollab = CollabDefinition(
  id: eventsTodayCollabId,
  title: 'Events heute',
  subtitle: 'Was heute los ist',
  creatorId: 'localspots',
  creatorName: 'LocalSpots',
  creatorAvatarUrl: null,
  heroType: 'gradient',
  gradientKey: 'sunset',
  query: CollabQuery(),
  limit: 30,
  requiresRuntime: false,
);

const CollabDefinition _eventsHighlightsYearCollab = CollabDefinition(
  id: eventsHighlightsYearCollabId,
  title: 'Highlights dieses Jahr',
  subtitle: 'Die wichtigsten Events des Jahres',
  creatorId: 'localspots',
  creatorName: 'LocalSpots',
  creatorAvatarUrl: null,
  heroType: 'gradient',
  gradientKey: 'mint',
  query: CollabQuery(),
  limit: 30,
  requiresRuntime: false,
);

class SystemCollabsStore {
  static List<CollabDefinition>? _cache;

  static Future<List<CollabDefinition>> load() async {
    if (_cache != null) return _cache!;
    if (!SupabaseGate.isEnabled) {
      final fallback = List<CollabDefinition>.from(collabDefinitions);
      fallback.insertAll(0, _defaultEventCollabs());
      _cache = fallback;
      return _cache!;
    }
    final supabase = SupabaseGate.client;
    final response = await supabase.from('system_collabs').select();
    final lists = (response as List?) ?? [];
    const gradientKeys = ['mint', 'sunset', 'calm', 'deep'];
    var gradientIndex = 0;
    final result = <CollabDefinition>[];

    for (final entry in lists) {
      if (entry is! Map) continue;
      final map = Map<String, dynamic>.from(entry);
      final listId = map['id']?.toString() ?? map['list_id']?.toString() ?? '';
      if (listId.isEmpty) continue;
      if (listId == 'spots_with_website') continue;
      final title = map['title']?.toString() ?? 'Empfohlen';
      final requiresRuntime = map['requires_runtime'] == true;
      final runtimeFilters = (map['runtime_filters'] as List? ?? [])
          .map((value) => value.toString())
          .toList();
      final ranking = (map['ranking'] as List? ?? [])
          .map((value) => value.toString())
          .toList();
      final spotPoolIds = _extractSpotPoolIds(map);
      final includeCategories = (map['include_categories'] as List? ?? [])
          .map((value) => value.toString())
          .toList();
      final excludeCategories = (map['exclude_categories'] as List? ?? [])
          .map((value) => value.toString())
          .toList();
      final minReviewCount = (map['min_review_count'] as num?)?.toInt() ?? 0;
      final onlySocialEnabled = map['only_social_enabled'] == true;
      final sort = map['sort']?.toString() ?? 'reviewCount';
      final limit = (map['limit'] as num?)?.toInt();

      final heroImageUrlRaw = map['hero_image_url']?.toString();
      final heroImageUrl =
          heroImageUrlRaw != null && heroImageUrlRaw.trim().isNotEmpty
              ? heroImageUrlRaw.trim()
              : null;
      final heroTypeRaw = map['hero_type']?.toString();
      final heroType = heroTypeRaw != null && heroTypeRaw.trim().isNotEmpty
          ? heroTypeRaw.trim()
          : (heroImageUrl != null ? 'image' : 'gradient');
      final gradientKeyRaw = map['gradient_key']?.toString();
      final gradientKey = gradientKeyRaw != null && gradientKeyRaw.trim().isNotEmpty
          ? gradientKeyRaw.trim()
          : gradientKeys[gradientIndex % gradientKeys.length];
      gradientIndex += 1;

      result.add(
        CollabDefinition(
          id: listId,
          title: title,
          subtitle: 'Von LocalSpots für dich',
          creatorId: 'localspots',
          creatorName: 'LocalSpots',
          creatorAvatarUrl: null,
          heroType: heroType,
          heroImageUrl: heroImageUrl,
          gradientKey: gradientKey,
          query: CollabQuery(
            includeCategories: includeCategories,
            excludeCategories: excludeCategories,
            minReviewCount: minReviewCount,
            onlySocialEnabled: onlySocialEnabled,
            sort: sort,
          ),
          limit: limit ?? spotPoolIds.length,
          spotPoolIds: spotPoolIds,
          requiresRuntime: requiresRuntime,
          runtimeFilters: runtimeFilters,
          ranking: ranking,
        ),
      );
    }

    _ensureDefaultEventCollabs(result);

    _cache = result;
    return result;
  }

  static void _ensureDefaultEventCollabs(List<CollabDefinition> collabs) {
    final existingIds = collabs.map((collab) => collab.id).toSet();
    final defaults = _defaultEventCollabs()
        .where((collab) => !existingIds.contains(collab.id))
        .toList();
    if (defaults.isEmpty) return;
    collabs.insertAll(0, defaults);
  }

  static List<CollabDefinition> _defaultEventCollabs() {
    return [
      _eventsTodayCollab,
      _eventsThisWeekCollab,
      _eventsHighlightsYearCollab,
    ];
  }

  static List<String> _extractSpotPoolIds(Map<String, dynamic> map) {
    final explicitIds = (map['spot_pool_ids'] as List? ?? [])
        .map((value) => value.toString())
        .where((value) => value.isNotEmpty)
        .toList();
    if (explicitIds.isNotEmpty) return explicitIds;

    final spotPool = (map['spot_pool'] as List? ?? []);
    return spotPool
        .map((value) {
          if (value is Map && value['id'] != null) {
            return value['id'].toString();
          }
          return null;
        })
        .whereType<String>()
        .toList();
  }

  static CollabDefinition? findById(String id) {
    final cached = _cache;
    if (cached == null) return null;
    for (final collab in cached) {
      if (collab.id == id) return collab;
    }
    return null;
  }

  static CollabDefinition? findByTitle(String title) {
    final cached = _cache;
    if (cached == null) return null;
    final normalized = title.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    for (final collab in cached) {
      if (collab.title.trim().toLowerCase() == normalized) {
        return collab;
      }
    }
    return null;
  }
}

