import 'package:flutter/material.dart';

import '../../models/pos_permission_catalog.dart';
import '../../models/pos_role.dart';
import '../../models/staff_user.dart';
import '../../services/pos_operations_service.dart';
import '../../services/restaurant_settings_service.dart';
import '../../services/super_admin_scope_service.dart';
import 'admin_corner_toast.dart';
import 'admin_responsive_layout.dart';
import 'pos/pos_add_staff_dialog.dart';
import 'pos/pos_staff_empty_state.dart';

class AdminPosRolesStaffCard extends StatefulWidget {
  const AdminPosRolesStaffCard({super.key});

  @override
  State<AdminPosRolesStaffCard> createState() => _AdminPosRolesStaffCardState();
}

class _AdminPosRolesStaffCardState extends State<AdminPosRolesStaffCard> {
  static const burgundy = Color(0xFF6B1124);

  var _loading = true;
  var _savingRoles = false;
  List<PosRole> _roles = PosRole.defaults();
  List<StaffUser> _staff = const [];
  int _autoLockMinutes = 5;

  @override
  void initState() {
    super.initState();
    _load();
    SuperAdminScopeService.instance.addListener(_onScopeChanged);
  }

  @override
  void dispose() {
    SuperAdminScopeService.instance.removeListener(_onScopeChanged);
    super.dispose();
  }

  void _onScopeChanged() => _load();

  PosRole _normalizeRole(PosRole role) {
    return role.copyWith(
      permissions: PosPermissionCatalog.normalizePermissions(role.permissions),
    );
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final settings = await RestaurantSettingsService.instance.load(
        restaurantId: SuperAdminScopeService.instance.effectiveRestaurantId,
      );
      final staff = await PosOperationsService.instance.fetchStaffUsers();
      if (!mounted) return;
      setState(() {
        _roles = settings.resolvedPosRoles.map(_normalizeRole).toList();
        _autoLockMinutes = settings.posAutoLockMinutes;
        _staff = staff;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _saveRoles() async {
    setState(() => _savingRoles = true);
    try {
      final scopedRestaurantId = SuperAdminScopeService.instance.effectiveRestaurantId;
      final current = await RestaurantSettingsService.instance.load(
        restaurantId: scopedRestaurantId,
      );
      final updated = current.copyWith(
        posRoles: _roles.map(_normalizeRole).toList(),
        posAutoLockMinutes: _autoLockMinutes,
        updatedAt: DateTime.now().toUtc(),
      );
      await RestaurantSettingsService.instance.savePosSettings(updated);
      if (!mounted) return;
      AdminCornerToast.success(context, 'تم حفظ صلاحيات POS');
    } catch (_) {
      if (!mounted) return;
      AdminCornerToast.error(context, 'تعذر حفظ صلاحيات POS');
    } finally {
      if (mounted) setState(() => _savingRoles = false);
    }
  }

  Future<void> _addStaff() async {
    try {
      final created = await showPosAddStaffDialog(context);
      if (created == null) return;

      await _load();
      if (!mounted) return;
      AdminCornerToast.success(context, 'تم إضافة الموظف');
    } catch (_) {
      if (!mounted) return;
      AdminCornerToast.error(context, 'تعذر إضافة الموظف');
    }
  }

  void _togglePermission(PosRole role, String permission, bool enabled) {
    setState(() {
      final index = _roles.indexWhere((entry) => entry.id == role.id);
      if (index == -1) return;
      final permissions = Map<String, bool>.from(_roles[index].permissions);
      permissions[permission] = enabled;
      _roles[index] = _normalizeRole(
        _roles[index].copyWith(permissions: permissions),
      );
    });
  }

  bool _canEditRole(PosRole role) {
    return !(role.isBuiltIn && role.id == 'pos_admin');
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: burgundy))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AdminSectionHeader(
                    icon: Icons.admin_panel_settings,
                    title: 'أدوار وصلاحيات POS',
                    subtitle:
                        'كل صلاحية في النظام لها مفتاح تحكم — لا صلاحيات مخفية',
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: _autoLockMinutes,
                    decoration: const InputDecoration(
                      labelText: 'قفل تلقائي بعد (دقائق)',
                      border: OutlineInputBorder(),
                    ),
                    items: const [3, 5, 10, 15, 30]
                        .map(
                          (m) => DropdownMenuItem(
                            value: m,
                            child: Text('$m دقائق'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _autoLockMinutes = value ?? 5),
                  ),
                  const SizedBox(height: 16),
                  ..._roles.map((role) => _buildRoleTile(role)),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: FilledButton.icon(
                      onPressed: _savingRoles ? null : _saveRoles,
                      icon: _savingRoles
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save),
                      label: const Text('حفظ التغييرات'),
                    ),
                  ),
                  const Divider(height: 32),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'موظفو POS',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: _addStaff,
                        icon: const Icon(Icons.person_add),
                        label: const Text('إضافة موظف'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_staff.isEmpty)
                    PosStaffEmptyState(
                      compact: true,
                      onStaffAdded: () async {
                        await _load();
                        if (!mounted) return;
                        AdminCornerToast.success(context, 'تم إضافة الموظف');
                      },
                    )
                  else
                    ..._staff.map(
                      (member) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(member.name),
                        subtitle: Text(roleLabelForStaff(member, roles: _roles)),
                        trailing: Icon(
                          member.isActive ? Icons.check_circle : Icons.cancel,
                          color: member.isActive ? Colors.green : Colors.grey,
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _buildRoleTile(PosRole role) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.hardEdge,
      child: ExpansionTile(
        title: Text(role.nameAr, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(role.nameEn),
        children: PosPermissionCategory.values
            .map((category) => _buildCategoryGroup(role, category))
            .toList(),
      ),
    );
  }

  Widget _buildCategoryGroup(PosRole role, PosPermissionCategory category) {
    final entries = PosPermissionCatalog.forCategory(category);
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: category == PosPermissionCategory.pos,
        tilePadding: const EdgeInsets.symmetric(horizontal: 20),
        title: Text(
          PosPermissionCatalog.categoryLabels[category] ?? category.name,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        children: entries
            .map(
              (entry) => SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                title: Text(entry.labelAr),
                subtitle: Text(
                  entry.key,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                value: role.allows(entry.key),
                onChanged: _canEditRole(role)
                    ? (value) => _togglePermission(role, entry.key, value)
                    : null,
              ),
            )
            .toList(),
      ),
    );
  }
}
