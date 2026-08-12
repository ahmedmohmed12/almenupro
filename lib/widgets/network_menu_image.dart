import 'package:flutter/material.dart';

import '../utils/image_url.dart';

import 'package:flutter/material.dart';
import '../utils/image_url.dart';

class NetworkMenuImage extends StatelessWidget {
  const NetworkMenuImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.errorBuilder,
    this.loadingBuilder,
  });

  final String imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final ImageErrorWidgetBuilder? errorBuilder;
  final ImageLoadingBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      resolveImageUrl(imageUrl),
      fit: fit,
      width: width,
      height: height,
      errorBuilder: errorBuilder,
      loadingBuilder: loadingBuilder,
    );
  }
}