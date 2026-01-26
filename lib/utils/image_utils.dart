import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

bool isAssetImage(String? url) {
  if (url == null) return false;
  final trimmed = url.trim();
  return trimmed.startsWith('asset:') || trimmed.startsWith('assets/');
}

String normalizeAssetPath(String url) {
  var trimmed = url.trim();
  if (trimmed.startsWith('asset://')) {
    trimmed = trimmed.substring('asset://'.length);
  } else if (trimmed.startsWith('asset:')) {
    trimmed = trimmed.substring('asset:'.length);
  }
  return trimmed;
}

ImageProvider? imageProviderFor(String? url) {
  if (url == null) return null;
  final trimmed = url.trim();
  if (trimmed.isEmpty) return null;
  if (isAssetImage(trimmed)) {
    return AssetImage(normalizeAssetPath(trimmed));
  }
  return NetworkImage(trimmed);
}

Future<ui.Image> loadUiImage(String url) async {
  if (isAssetImage(url)) {
    final data = await rootBundle.load(normalizeAssetPath(url));
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    return frame.image;
  }
  final uri = Uri.parse(url);
  final bundle = NetworkAssetBundle(uri);
  final data = await bundle.load(url);
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
  final frame = await codec.getNextFrame();
  return frame.image;
}



