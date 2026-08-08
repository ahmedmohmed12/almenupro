import 'package:flutter/material.dart';

import 'admin_breakpoints.dart';

/// Page padding + optional vertical scroll for admin tab content.
class AdminResponsivePage extends StatelessWidget {
  const AdminResponsivePage({
    super.key,
    required this.child,
    this.scrollable = false,
    this.padding,
  });

  final Widget child;
  final bool scrollable;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final pad = padding ?? EdgeInsets.all(AdminBreakpoints.pagePadding(context));
    final content = Padding(padding: pad, child: child);

    if (!scrollable) return content;

    return SingleChildScrollView(
      primary: false,
      child: content,
    );
  }
}

/// Toolbar row: icon + title block + trailing actions; wraps on narrow widths.
class AdminSectionHeader extends StatelessWidget {
  const AdminSectionHeader({
    super.key,
    this.icon,
    this.iconColor,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });

  final IconData? icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final narrow = AdminBreakpoints.isNarrowContent(context);

    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Color(0xFF6B1124),
          ),
        ),
        if (subtitle != null && subtitle!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: Color(0xFF666666)),
          ),
        ],
      ],
    );

    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) ...[
                _iconBox(icon!, iconColor),
                const SizedBox(width: 12),
              ],
              Expanded(child: titleBlock),
            ],
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          _iconBox(icon!, iconColor),
          const SizedBox(width: 12),
        ],
        Expanded(child: titleBlock),
        if (actions.isNotEmpty) ...[
          const SizedBox(width: 8),
          Wrap(spacing: 4, runSpacing: 4, children: actions),
        ],
      ],
    );
  }

  Widget _iconBox(IconData data, Color? color) {
    final c = color ?? const Color(0xFF6B1124);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(data, color: c),
    );
  }
}

/// Responsive grid — auto-fit columns by minimum tile width.
class AdminResponsiveGrid extends StatelessWidget {
  const AdminResponsiveGrid({
    super.key,
    required this.children,
    this.minTileWidth = 200,
    this.spacing = 12,
    this.runSpacing = 12,
  });

  final List<Widget> children;
  final double minTileWidth;
  final double spacing;
  final double runSpacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final columns = AdminBreakpoints.gridColumnCount(
          maxWidth,
          minTileWidth: minTileWidth,
        );
        final tileWidth =
            (maxWidth - spacing * (columns - 1).clamp(0, columns)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: children
              .map((child) => SizedBox(width: tileWidth, child: child))
              .toList(),
        );
      },
    );
  }
}

/// Horizontally scrollable table container — prevents page-level overflow.
class AdminScrollableTable extends StatelessWidget {
  const AdminScrollableTable({
    super.key,
    required this.child,
    this.minTableWidth = 960,
  });

  final Widget child;
  final double minTableWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final tableWidth = minTableWidth > viewport ? minTableWidth : viewport;

        return Card(
          clipBehavior: Clip.antiAlias,
          child: Scrollbar(
            thumbVisibility: viewport < minTableWidth,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              primary: false,
              child: SizedBox(
                width: tableWidth,
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Keeps tab content within available width (sidebar-aware).
class AdminContentWidthLimiter extends StatelessWidget {
  const AdminContentWidthLimiter({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          width: constraints.maxWidth,
          child: child,
        );
      },
    );
  }
}
