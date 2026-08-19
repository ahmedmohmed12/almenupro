import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../utils/image_url.dart';

class NetworkMenuImage extends StatelessWidget {
  const NetworkMenuImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.cacheWidth,
    this.cacheHeight,
    this.errorBuilder,
    this.loadingBuilder,
  });

  final String imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final int? cacheWidth;
  final int? cacheHeight;
  final ImageErrorWidgetBuilder? errorBuilder;
  final ImageLoadingBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    final resolved = resolveImageUrl(imageUrl);
    final uri = Uri.tryParse(resolved);
    final canLoad = resolved.isNotEmpty &&
        uri != null &&
        (uri.isScheme('http') || uri.isScheme('https'));

    if (!canLoad) {
      return _fallback(context);
    }

    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    final decodedWidth = kIsWeb
        ? null
        : cacheWidth ??
            (width != null && width!.isFinite ? (width! * dpr).round() : 240);
    final decodedHeight = kIsWeb
        ? null
        : cacheHeight ??
            (height != null && height!.isFinite ? (height! * dpr).round() : null);

    try {
      return Image.network(
        resolved,
        fit: fit,
        width: width,
        height: height,
        cacheWidth: decodedWidth != null && decodedWidth > 0 ? decodedWidth : null,
        cacheHeight:
            decodedHeight != null && decodedHeight > 0 ? decodedHeight : null,
        filterQuality: FilterQuality.low,
        gaplessPlayback: true,
        errorBuilder: errorBuilder ?? (_, __, ___) => _fallback(context),
        loadingBuilder: loadingBuilder ??
            (context, child, progress) {
              if (progress == null) return child;
              return ColoredBox(
                color: const Color(0xFFF4ECE9),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Theme.of(context).colorScheme.primary,
                      value: progress.expectedTotalBytes != null
                          ? progress.cumulativeBytesLoaded /
                              progress.expectedTotalBytes!
                          : null,
                    ),
                  ),
                ),
              );
            },
      );
    } catch (_) {
      return _fallback(context);
    }
  }

  Widget _fallback(BuildContext context) {
    if (errorBuilder != null) {
      return errorBuilder!(context, Exception('image'), StackTrace.empty);
    }
    return const ColoredBox(
      color: Color(0xFFF4ECE9),
      child: Center(
        child: Icon(Icons.restaurant, color: Color(0xFF6B1124)),
      ),
    );
  }
}
