class ContentFilter {
  ContentFilter._();

  static const List<String> _blockedTerms = [
    'nazi',
    'hitler',
    'heil',
    'terror',
    'bomb',
    'kill',
    'rape',
    'sex',
    'porn',
    'nude',
    'asshole',
    'bitch',
    'bastard',
    'fuck',
    'shit',
    'slut',
  ];

  static bool containsObjectionable(String? value) {
    final normalized = value?.toLowerCase().trim();
    if (normalized == null || normalized.isEmpty) {
      return false;
    }
    for (final term in _blockedTerms) {
      if (normalized.contains(term)) {
        return true;
      }
    }
    return false;
  }
}



