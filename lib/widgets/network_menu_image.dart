import 'package:flutter/material.dart';

import '../utils/image_url.dart';

class NetworkMenuImage extends StatelessWidget {
  const NetworkMenuImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.errorBuilder,
    this.loadingBuilder,
  });

  final String imageUrl;
  final BoxFit fit;
  final ImageErrorWidgetBuilder? errorBuilder;
  final ImageLoadingBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      resolveImageUrl(imageUrl),
      fit: fit,
      errorBuilder: errorBuilder,
      loadingBuilder: loadingBuilder,
    );
  }
}
