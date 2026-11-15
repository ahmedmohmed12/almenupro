import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// In-page modal overlay that stays in the widget tree (Offstage) for instant open.
class PosInPageOverlay extends StatelessWidget {
  const PosInPageOverlay({
    super.key,
    required this.visible,
    required this.title,
    required this.onClose,
    required this.child,
  });

  final bool visible;
  final String title;
  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Offstage(
      offstage: !visible,
      child: TickerMode(
        enabled: visible,
        child: IgnorePointer(
          ignoring: !visible,
          child: _Sheet(
            visible: visible,
            title: title,
            onClose: onClose,
            child: child,
          ),
        ),
      ),
    );
  }
}

class _Sheet extends StatelessWidget {
  const _Sheet({
    required this.visible,
    required this.title,
    required this.onClose,
    required this.child,
  });

  final bool visible;
  final String title;
  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final mobile = width < 768;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): onClose,
      },
      child: Focus(
        autofocus: visible,
        child: Material(
          color: Colors.black.withValues(alpha: 0.38),
          child: SafeArea(
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onClose,
                  ),
                ),
                Align(
                  alignment: mobile ? Alignment.bottomCenter : Alignment.center,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: mobile ? 0 : 24,
                      vertical: mobile ? 0 : 20,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: mobile ? double.infinity : 1100,
                        maxHeight: mobile
                            ? MediaQuery.sizeOf(context).height * 0.94
                            : MediaQuery.sizeOf(context).height * 0.9,
                      ),
                      child: Material(
                        color: const Color(0xFFF4F6F8),
                        elevation: 12,
                        borderRadius: BorderRadius.vertical(
                          top: const Radius.circular(18),
                          bottom: Radius.circular(mobile ? 0 : 18),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Material(
                              color: const Color(0xFF2C353F),
                              child: SizedBox(
                                height: 52,
                                child: Row(
                                  children: [
                                    IconButton(
                                      tooltip: 'إغلاق',
                                      onPressed: onClose,
                                      icon: const Icon(
                                        Icons.close,
                                        color: Colors.white,
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        title,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Expanded(child: child),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
