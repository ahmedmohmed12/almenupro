import '../models/cart_item.dart';

enum KitchenModificationKind { add, change, voidLine }

class KitchenModificationLine {
  const KitchenModificationLine({
    required this.kind,
    required this.name,
    required this.quantity,
    this.notes,
    this.detail,
  });

  final KitchenModificationKind kind;
  final String name;
  final int quantity;
  final String? notes;
  final String? detail;
}

class KitchenModificationDelta {
  const KitchenModificationDelta({
    this.added = const [],
    this.changed = const [],
    this.voided = const [],
  });

  final List<KitchenModificationLine> added;
  final List<KitchenModificationLine> changed;
  final List<KitchenModificationLine> voided;

  bool get isEmpty =>
      added.isEmpty && changed.isEmpty && voided.isEmpty;

  bool get hasKitchenRelevantChange =>
      added.isNotEmpty || changed.isNotEmpty || voided.isNotEmpty;
}

String _optionsSignature(List<SelectedOption> options) {
  return options.map((o) => '${o.group}:${o.name}:${o.price}').join('|');
}

/// Kitchen ticket delta after at least one line was already sent to kitchen.
KitchenModificationDelta computeKitchenModificationDelta(
  List<CartItem> before,
  List<CartItem> after,
) {
  if (!before.any((line) => line.isSentToKitchen)) {
    return const KitchenModificationDelta();
  }

  final beforeById = {for (final line in before) line.id: line};
  final afterById = {for (final line in after) line.id: line};

  final added = <KitchenModificationLine>[];
  final changed = <KitchenModificationLine>[];
  final voided = <KitchenModificationLine>[];

  for (final cur in after) {
    final prev = beforeById[cur.id];
    if (prev == null) {
      added.add(
        KitchenModificationLine(
          kind: KitchenModificationKind.add,
          name: cur.menuItem.name,
          quantity: cur.quantity,
          notes: cur.specialNotes,
          detail: 'صنف جديد',
        ),
      );
      continue;
    }

    if (cur.quantity > prev.quantity) {
      added.add(
        KitchenModificationLine(
          kind: KitchenModificationKind.add,
          name: cur.menuItem.name,
          quantity: cur.quantity - prev.quantity,
          notes: cur.specialNotes,
          detail: 'زيادة كمية',
        ),
      );
    }

    final notesChanged =
        (prev.specialNotes ?? '').trim() != (cur.specialNotes ?? '').trim();
    final optionsChanged =
        _optionsSignature(prev.selectedOptions) !=
        _optionsSignature(cur.selectedOptions);
    if (prev.isSentToKitchen && (notesChanged || optionsChanged)) {
      changed.add(
        KitchenModificationLine(
          kind: KitchenModificationKind.change,
          name: cur.menuItem.name,
          quantity: cur.quantity,
          notes: cur.specialNotes,
          detail: notesChanged && optionsChanged
              ? 'تعديل ملاحظات وخيارات'
              : notesChanged
              ? 'تعديل ملاحظات'
              : 'تعديل خيارات',
        ),
      );
    }
  }

  for (final prev in before) {
    if (!prev.isSentToKitchen) continue;
    final cur = afterById[prev.id];
    if (cur == null) {
      voided.add(
        KitchenModificationLine(
          kind: KitchenModificationKind.voidLine,
          name: prev.menuItem.name,
          quantity: prev.quantity,
          notes: prev.specialNotes,
          detail: 'إلغاء',
        ),
      );
      continue;
    }
    if (cur.quantity < prev.quantity) {
      voided.add(
        KitchenModificationLine(
          kind: KitchenModificationKind.voidLine,
          name: prev.menuItem.name,
          quantity: prev.quantity - cur.quantity,
          notes: prev.specialNotes,
          detail: 'تقليل كمية',
        ),
      );
    }
  }

  return KitchenModificationDelta(
    added: added,
    changed: changed,
    voided: voided,
  );
}