import 'package:flutter/material.dart';

import '../../models/expense.dart';
import '../../services/admin_auth_service.dart';
import '../../services/api_service.dart';
import '../../services/super_admin_scope_service.dart';
import '../../theme/app_theme.dart';
import 'admin_profit_loss_card.dart';
import 'admin_responsive_layout.dart';

class AdminExpensesPanel extends StatefulWidget {
  const AdminExpensesPanel({super.key});

  @override
  State<AdminExpensesPanel> createState() => _AdminExpensesPanelState();
}

class _AdminExpensesPanelState extends State<AdminExpensesPanel> {
  var _loading = true;
  String? _error;
  String? _category;
  List<ExpenseRecord> _expenses = const [];

  String get _restaurantId {
    if (AdminAuthService.instance.isRestaurantAdmin) {
      return AdminAuthService.instance.restaurantId ??
          ApiService.defaultRestaurantId;
    }
    return SuperAdminScopeService.instance.effectiveRestaurantId;
  }

  @override
  void initState() {
    super.initState();
    SuperAdminScopeService.instance.addListener(_onScopeChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    SuperAdminScopeService.instance.removeListener(_onScopeChanged);
    super.dispose();
  }

  void _onScopeChanged() => _load();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final expenses = await ApiService.instance.fetchExpenses(
        restaurantId: _restaurantId,
        category: _category,
      );
      if (!mounted) return;
      setState(() {
        _expenses = expenses;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _confirmDelete(ExpenseRecord expense) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف المصروف'),
        content: Text('حذف "${expense.title}"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService.instance.deleteExpense(
        expense.id,
        restaurantId: _restaurantId,
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _openEditor() async {
    final created = await showDialog<ExpenseRecord>(
      context: context,
      builder: (context) => const _ExpenseEditorDialog(),
    );
    if (created == null) return;
    try {
      await ApiService.instance.createExpense(
        created,
        restaurantId: _restaurantId,
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final needsSelection = AdminAuthService.instance.isSuperAdmin &&
        !SuperAdminScopeService.instance.hasEffectiveRestaurant;

    return AdminResponsivePage(
      scrollable: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminSectionHeader(
            icon: Icons.account_balance_wallet_outlined,
            title: 'إدارة المصاريف',
            subtitle: 'سجّل المصروفات واطّلع على صافي الربح والخسارة تلقائياً',
            actions: [
              FilledButton.icon(
                onPressed: needsSelection ? null : _openEditor,
                icon: const Icon(Icons.add),
                label: const Text('إضافة مصروف'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (needsSelection)
            const Text(
              'اختر مطعماً من الشريط الجانبي لعرض المصاريف والتقارير المالية.',
              style: TextStyle(color: Colors.orange),
            )
          else ...[
            const AdminProfitLossCard(),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              children: [
                FilterChip(
                  label: const Text('الكل'),
                  selected: _category == null,
                  onSelected: (_) {
                    setState(() => _category = null);
                    _load();
                  },
                ),
                ...expenseCategoryKeys.map(
                  (key) => FilterChip(
                    label: Text(expenseCategoryLabel(key)),
                    selected: _category == key,
                    onSelected: (_) {
                      setState(() => _category = key);
                      _load();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: CircularProgressIndicator(color: AppTheme.brandOrange),
                ),
              )
            else if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red))
            else if (_expenses.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('لا توجد مصاريف في هذا التصنيف بعد.'),
              )
            else
              ..._expenses.map(
                (expense) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppTheme.brandMaroon.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              expense.title,
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${expenseCategoryLabel(expense.category)} · ${expense.date}',
                              style: const TextStyle(color: Color(0xFF666666)),
                            ),
                            if (expense.notes.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(expense.notes),
                            ],
                          ],
                        ),
                      ),
                      Text(
                        '${expense.amount.toStringAsFixed(3)} د.ك',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF6B1124),
                        ),
                      ),
                      IconButton(
                        onPressed: () => _confirmDelete(expense),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _ExpenseEditorDialog extends StatefulWidget {
  const _ExpenseEditorDialog();

  @override
  State<_ExpenseEditorDialog> createState() => _ExpenseEditorDialogState();
}

class _ExpenseEditorDialogState extends State<_ExpenseEditorDialog> {
  final _title = TextEditingController();
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  String _category = 'suppliers';
  DateTime _date = DateTime.now();

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    if (_title.text.trim().isEmpty || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل العنوان ومبلغاً أكبر من صفر')),
      );
      return;
    }
    final iso = _date.toIso8601String().sliceDate();
    Navigator.pop(
      context,
      ExpenseRecord(
        id: '',
        title: _title.text.trim(),
        category: _category,
        amount: amount,
        date: iso,
        notes: _notes.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إضافة مصروف'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'العنوان'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _category,
                items: [
                  for (final key in expenseCategoryKeys)
                    DropdownMenuItem(
                      value: key,
                      child: Text(expenseCategoryLabel(key)),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _category = value);
                },
                decoration: const InputDecoration(labelText: 'التصنيف'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'المبلغ (د.ك)'),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('التاريخ: ${_date.toIso8601String().sliceDate()}'),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) setState(() => _date = picked);
                },
              ),
              TextField(
                controller: _notes,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'ملاحظات'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(onPressed: _submit, child: const Text('حفظ')),
      ],
    );
  }
}

extension on String {
  String sliceDate() => length >= 10 ? substring(0, 10) : this;
}
