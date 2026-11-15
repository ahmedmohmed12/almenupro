import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../models/restaurant.dart';
import '../../services/restaurant_login_search.dart';
import 'admin_login_theme.dart';

/// Slug field with a floating overlay list (does not reflow fields below).
class RestaurantSlugSearchField extends StatefulWidget {
  const RestaurantSlugSearchField({
    super.key,
    required this.controller,
    required this.focusNode,
    this.errorText,
    this.onSelected,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String? errorText;
  final ValueChanged<Restaurant>? onSelected;

  @override
  State<RestaurantSlugSearchField> createState() =>
      _RestaurantSlugSearchFieldState();
}

class _RestaurantSlugSearchFieldState extends State<RestaurantSlugSearchField> {
  final _layerLink = LayerLink();
  final _fieldKey = GlobalKey();
  OverlayEntry? _overlay;
  List<Restaurant> _catalog = const [];
  List<Restaurant> _matches = const [];
  var _loadingCatalog = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
    widget.controller.addListener(_onQuery);
    unawaited(_loadCatalog());
  }

  @override
  void dispose() {
    _removeOverlay();
    widget.focusNode.removeListener(_onFocus);
    widget.controller.removeListener(_onQuery);
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    try {
      final rows = await loadRestaurantsForLogin();
      if (!mounted) return;
      setState(() {
        _catalog = rows;
        _loadingCatalog = false;
      });
      _refreshMatches();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error.toString().replaceFirst('Exception: ', '');
        _loadingCatalog = false;
      });
    }
  }

  void _onFocus() {
    if (widget.focusNode.hasFocus) {
      _refreshMatches();
      _showOverlay();
    } else {
      Future<void>.delayed(const Duration(milliseconds: 120), () {
        if (mounted && !widget.focusNode.hasFocus) _removeOverlay();
      });
    }
  }

  void _onQuery() {
    _refreshMatches();
    if (widget.focusNode.hasFocus) {
      _markOverlayNeedsBuild();
    }
  }

  void _refreshMatches() {
    _matches = filterRestaurantsForLogin(_catalog, widget.controller.text);
  }

  void _select(Restaurant restaurant) {
    widget.controller.text = restaurant.slug;
    widget.onSelected?.call(restaurant);
    _removeOverlay();
    widget.focusNode.unfocus();
    setState(() {});
  }

  void _showOverlay() {
    _removeOverlay();
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
  final s = AppStrings.of(context);
    final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    final width = box?.size.width ?? 320;
    _overlay = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: _removeOverlay,
                behavior: HitTestBehavior.translucent,
                child: const SizedBox.expand(),
              ),
            ),
            CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              offset: const Offset(0, 56),
              child: Material(
                elevation: 10,
                shadowColor: Colors.black26,
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: 240, minWidth: width, maxWidth: width),
                  child: _buildOptions(s),
                ),
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(_overlay!);
  }

  Widget _buildOptions(AppStrings s) {
    if (_loadingCatalog) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AdminLoginTheme.burgundy,
            ),
          ),
        ),
      );
    }
    if (_loadError != null) {
      return Padding(
        padding: const EdgeInsets.all(14),
        child: Text(
          _loadError!,
          style: const TextStyle(color: Colors.redAccent, fontSize: 13),
        ),
      );
    }
    final query = widget.controller.text.trim();
    if (query.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(14),
        child: Text(
          s.tr('ابدأ الكتابة للبحث عن مطعمك', 'Type to find your restaurant'),
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        ),
      );
    }
    if (_matches.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(14),
        child: Text(
          s.tr('لا توجد مطابقة', 'No matches'),
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 6),
      shrinkWrap: true,
      itemCount: _matches.length,
      separatorBuilder: (_, index) => Divider(
        height: 1,
        color: Colors.grey.shade200,
      ),
      itemBuilder: (context, index) {
        final row = _matches[index];
        return ListTile(
          dense: true,
          leading: const Icon(Icons.store_mall_directory_outlined, color: AdminLoginTheme.burgundy),
          title: Text(row.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(row.slug, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          onTap: () => _select(row),
        );
      },
    );
  }

  void _markOverlayNeedsBuild() {
    _overlay?.markNeedsBuild();
    final query = widget.controller.text.trim();
    if (query.isNotEmpty &&
        _matches.isNotEmpty &&
        widget.focusNode.hasFocus &&
        _overlay == null) {
      _showOverlay();
    }
    if (query.isEmpty) {
      _removeOverlay();
      if (widget.focusNode.hasFocus) _showOverlay();
    }
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return CompositedTransformTarget(
      link: _layerLink,
      child: SizedBox(
        key: _fieldKey,
        width: double.infinity,
        child: TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        textInputAction: TextInputAction.next,
        decoration: AdminLoginTheme.fieldDecoration(
          label: s.tr('معرف المطعم (slug)', 'Restaurant slug'),
          hint: s.tr('ابحث عن المطعم أو اكتب المعرف...', 'Search or type restaurant slug...'),
          error: widget.errorText,
          trailingIcon: const Icon(Icons.store_outlined, color: AdminLoginTheme.burgundy),
        ),
      ),
      ),
    );
  }
}