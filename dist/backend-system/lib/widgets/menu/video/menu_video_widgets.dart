import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../models/menu_item.dart';
import '../../../theme/app_theme.dart';
import '../../network_menu_image.dart';

String resolveMenuVideoUrl(String raw) {
  final value = raw.trim();
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !uri.hasScheme ||
      (uri.scheme != 'https' && uri.scheme != 'http')) {
    return '';
  }
  return uri.toString();
}

class ItemVideoBadge extends StatelessWidget {
  const ItemVideoBadge({
    super.key,
    required this.item,
    this.compact = false,
  });

  final MenuItem item;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (!item.hasVideo) return const SizedBox.shrink();
    return Material(
      color: Colors.black.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () => showItemVideoModal(context, item),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 7 : 9,
            vertical: compact ? 5 : 6,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.play_circle_fill_rounded,
                color: Colors.white,
                size: compact ? 15 : 17,
              ),
              const SizedBox(width: 4),
              Text(
                compact ? 'فيديو' : 'شاهد الفيديو',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 10.5 : 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showItemVideoModal(BuildContext context, MenuItem item) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      backgroundColor: Colors.black,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 9 / 16,
              child: LazyVideoPlayer(item: item),
            ),
            Container(
              color: const Color(0xFF151515),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'إغلاق',
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class LazyVideoPlayer extends StatefulWidget {
  const LazyVideoPlayer({super.key, required this.item});

  final MenuItem item;

  @override
  State<LazyVideoPlayer> createState() => _LazyVideoPlayerState();
}

class _LazyVideoPlayerState extends State<LazyVideoPlayer> {
  VideoPlayerController? _controller;
  var _loading = true;
  var _failed = false;
  var _muted = true;
  var _attempt = 0;

  List<String> get _sources => [
    resolveMenuVideoUrl(widget.item.videoUrlWebm),
    resolveMenuVideoUrl(widget.item.videoUrlMp4),
  ].where((url) => url.isNotEmpty).toSet().toList();

  @override
  void initState() {
    super.initState();
    unawaited(_openNextSource());
  }

  Future<void> _openNextSource() async {
    if (_attempt >= _sources.length) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
      return;
    }

    final url = _sources[_attempt++];
    final previous = _controller;
    _controller = null;
    await previous?.dispose();

    final controller = VideoPlayerController.networkUrl(
      Uri.parse(url),
      videoPlayerOptions: VideoPlayerOptions(
        mixWithOthers: true,
        allowBackgroundPlayback: false,
      ),
    );
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _loading = false;
        _failed = false;
      });
    } catch (_) {
      await controller.dispose();
      await _openNextSource();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _toggleMute() async {
    final controller = _controller;
    if (controller == null) return;
    _muted = !_muted;
    await controller.setVolume(_muted ? 0 : 1);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_failed)
            widget.item.imageUrl.trim().isEmpty
                ? const Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white54,
                      size: 44,
                    ),
                  )
                : NetworkMenuImage(
                    imageUrl: widget.item.imageUrl,
                    fit: BoxFit.cover,
                  )
          else if (controller != null && controller.value.isInitialized)
            FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: controller.value.size.width,
                height: controller.value.size.height,
                child: VideoPlayer(controller),
              ),
            ),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(color: AppTheme.brandOrange),
            ),
          if (controller != null && !_failed)
            PositionedDirectional(
              top: 10,
              end: 10,
              child: Material(
                color: Colors.black54,
                shape: const CircleBorder(),
                child: IconButton(
                  onPressed: _toggleMute,
                  tooltip: _muted ? 'تشغيل الصوت' : 'كتم الصوت',
                  icon: Icon(
                    _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class FeaturedStoriesBar extends StatelessWidget {
  const FeaturedStoriesBar({
    super.key,
    required this.items,
    required this.onAdd,
  });

  final List<MenuItem> items;
  final ValueChanged<MenuItem> onAdd;

  @override
  Widget build(BuildContext context) {
    final stories = items
        .where((item) => item.isStory && item.hasVideo)
        .toList(growable: false);
    if (stories.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 112,
      child: ListView.separated(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 8),
        scrollDirection: Axis.horizontal,
        itemCount: stories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final item = stories[index];
          return InkWell(
            onTap: () => showStoryViewer(context, item, onAdd),
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 72,
              child: Column(
                children: [
                  Container(
                    width: 66,
                    height: 66,
                    padding: const EdgeInsets.all(2.5),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.brandOrange,
                          AppTheme.brandMaroon,
                        ],
                      ),
                    ),
                    child: ClipOval(
                      child: item.imageUrl.trim().isEmpty
                          ? const ColoredBox(
                              color: AppTheme.brandSurface,
                              child: Icon(Icons.restaurant),
                            )
                          : NetworkMenuImage(
                              imageUrl: item.imageUrl,
                              fit: BoxFit.cover,
                            ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

Future<void> showStoryViewer(
  BuildContext context,
  MenuItem item,
  ValueChanged<MenuItem> onAdd,
) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Stack(
              fit: StackFit.expand,
              children: [
                LazyVideoPlayer(item: item),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x55000000),
                        Colors.transparent,
                        Color(0xCC000000),
                      ],
                    ),
                  ),
                ),
                PositionedDirectional(
                  top: 8,
                  end: 8,
                  child: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white, size: 30),
                  ),
                ),
                PositionedDirectional(
                  start: 20,
                  end: 20,
                  bottom: 24,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          onAdd(item);
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.brandOrange,
                          minimumSize: const Size.fromHeight(52),
                        ),
                        icon: const Icon(Icons.add_shopping_cart_rounded),
                        label: const Text(
                          'أضف إلى الطلب',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
