import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/restaurant.dart';
import '../../services/api_service.dart';
import '../../services/super_admin_scope_service.dart';
import '../../services/talabat_menu_service.dart';
import '../../utils/restaurant_route.dart';
import '../../utils/restaurant_slug.dart';

class AdminSuperRestaurantsPanel extends StatefulWidget {
  const AdminSuperRestaurantsPanel({super.key});

  @override
  State<AdminSuperRestaurantsPanel> createState() =>
      _AdminSuperRestaurantsPanelState();
}

class _AdminSuperRestaurantsPanelState extends State<AdminSuperRestaurantsPanel> {
  static const burgundy = Color(0xFF6B1124);

  final _nameController = TextEditingController();
  final _slugController = TextEditingController();
  final _ownerController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _subscriptionNotesController = TextEditingController();
  final _subscriptionExpiryController = TextEditingController();

  List<Restaurant> _restaurants = [];
  Restaurant? _editingRestaurant;
  var _loading = true;
  var _saving = false;
  String? _errorMessage;
  StorageHealth? _storageHealth;

  RestaurantStatus _status = RestaurantStatus.active;
  SubscriptionPlan _subscriptionPlan = SubscriptionPlan.free;
  SubscriptionStatus _subscriptionStatus = SubscriptionStatus.active;

  bool get _isEditMode => _editingRestaurant != null;

  @override
  void initState() {
    super.initState();
    _loadRestaurants();
    _loadStorageHealth();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _slugController.dispose();
    _ownerController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _subscriptionNotesController.dispose();
    _subscriptionExpiryController.dispose();
    super.dispose();
  }

  Future<void> _loadStorageHealth() async {
    try {
      final health = await ApiService.instance.fetchStorageHealth();
      if (mounted) setState(() => _storageHealth = health);
    } catch (_) {
      if (mounted) {
        setState(
          () => _storageHealth = const StorageHealth(
            ok: false,
            storage: 'unknown',
            persistent: false,
            message: 'تعذر التحقق من وضع التخزين',
          ),
        );
      }
    }
  }

  Future<void> _loadRestaurants() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      _restaurants = await ApiService.instance.fetchRestaurants();
    } catch (error) {
      _errorMessage = error.toString().replaceFirst('Exception: ', '');
      _restaurants = [];
    }

    if (mounted) setState(() => _loading = false);
  }

  void _resetForm() {
    setState(() {
      _editingRestaurant = null;
      _nameController.clear();
      _slugController.clear();
      _ownerController.clear();
      _phoneController.clear();
      _passwordController.clear();
      _subscriptionNotesController.clear();
      _subscriptionExpiryController.clear();
      _status = RestaurantStatus.active;
      _subscriptionPlan = SubscriptionPlan.free;
      _subscriptionStatus = SubscriptionStatus.active;
    });
  }

  void _loadRestaurantIntoForm(Restaurant restaurant) {
    setState(() {
      _editingRestaurant = restaurant;
      _nameController.text = restaurant.name;
      _slugController.text = restaurant.slug;
      _ownerController.text = restaurant.ownerName;
      _phoneController.text = restaurant.phone;
      _passwordController.clear();
      _subscriptionNotesController.text = restaurant.subscriptionNotes;
      _subscriptionExpiryController.text = restaurant.subscriptionExpiresAt == null
          ? ''
          : _formatDateInput(restaurant.subscriptionExpiresAt!);
      _status = restaurant.status;
      _subscriptionPlan = restaurant.subscriptionPlan;
      _subscriptionStatus = restaurant.subscriptionStatus;
    });
  }

  String _formatDateInput(DateTime value) {
    final local = value.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  DateTime? _parseExpiryDate() {
    final raw = _subscriptionExpiryController.text.trim();
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  Future<void> _saveRestaurant() async {
    final name = _nameController.text.trim();
    final slug = normalizeRestaurantSlug(
      _slugController.text,
      fallbackName: name,
    );
    final ownerName = _ownerController.text.trim();
    final phone = _phoneController.text.trim();
    final password = _passwordController.text.trim();
    final subscriptionNotes = _subscriptionNotesController.text.trim();
    final subscriptionExpiresAt = _parseExpiryDate();

    if (name.isEmpty || slug.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إدخال اسم المطعم ومعرف slug'),
        ),
      );
      return;
    }

    if (!_isEditMode && password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('كلمة مرور مدير المطعم مطلوبة عند الإنشاء')),
      );
      return;
    }

    if (_storageHealth != null && !_storageHealth!.persistent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFC62828),
          duration: Duration(seconds: 6),
          content: Text(
            'لا يمكن حفظ المطاعم حالياً: السيرفر بدون MongoDB. '
            'أضف MONGODB_URI في Vercel ثم Redeploy.',
          ),
        ),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final Restaurant saved;
      if (_isEditMode) {
        saved = await ApiService.instance.updateRestaurant(
          id: _editingRestaurant!.id,
          name: name,
          slug: slug,
          ownerName: ownerName,
          phone: phone,
          status: _status,
          subscriptionPlan: _subscriptionPlan,
          subscriptionStatus: _subscriptionStatus,
          subscriptionExpiresAt: subscriptionExpiresAt,
          subscriptionNotes: subscriptionNotes,
          adminPassword: password.isEmpty ? null : password,
        );
      } else {
        saved = await ApiService.instance.createRestaurant(
          name: name,
          slug: slug,
          adminPassword: password,
          ownerName: ownerName,
          phone: phone,
          status: _status,
          subscriptionPlan: _subscriptionPlan,
          subscriptionStatus: _subscriptionStatus,
          subscriptionExpiresAt: subscriptionExpiresAt,
          subscriptionNotes: subscriptionNotes,
        );
      }

      await _loadRestaurants();
      await SuperAdminScopeService.instance.refreshRestaurants();
      _loadRestaurantIntoForm(saved);

      if (!mounted) return;

      final menuPath = RestaurantRoute.menuPathForSlug(saved.slug);
      final menuUrl = kIsWeb ? '${Uri.base.origin}$menuPath' : menuPath;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF2E7D32),
          duration: const Duration(seconds: 5),
          content: Text(
            _isEditMode
                ? 'تم تحديث "${saved.name}" بنجاح.\nرابط العملاء: $menuUrl'
                : 'تم إنشاء "${saved.name}" بنجاح.\nslug: ${saved.slug}\nرابط العملاء: $menuUrl',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFC62828),
          duration: const Duration(seconds: 6),
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _importTalabatForRestaurant(Restaurant restaurant) async {
    final urlController = TextEditingController();
    var isLoading = false;
    String? statusMessage;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('استيراد منيو ${restaurant.name}'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'أدخل رابط Talabat (طلبات) لسحب الأصناف والصور وربطها بهذا المطعم:',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: urlController,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: 'رابط المنيو',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (statusMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(statusMessage!),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isLoading ? null : () => Navigator.pop(ctx),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: burgundy),
                  onPressed: isLoading
                      ? null
                      : () async {
                          final url = urlController.text.trim();
                          if (url.isEmpty) return;

                          setDialogState(() {
                            isLoading = true;
                            statusMessage = 'جاري السحب...';
                          });

                          await processAndSaveTalabatMenu(
                            url: url,
                            restaurantId: restaurant.id,
                            onProgress: (msg) {
                              setDialogState(() => statusMessage = msg);
                            },
                            onComplete: (added, skipped, updated) {
                              setDialogState(() {
                                isLoading = false;
                                statusMessage =
                                    'تم: $added جديد، $updated محدّث، $skipped موجود';
                              });
                            },
                          );
                        },
                  child: Text(
                    isLoading ? 'جاري...' : 'بدء الاستيراد',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    urlController.dispose();
  }

  Color _statusColor(RestaurantStatus status) {
    switch (status) {
      case RestaurantStatus.active:
        return const Color(0xFF2E7D32);
      case RestaurantStatus.inactive:
        return const Color(0xFF757575);
      case RestaurantStatus.suspended:
        return const Color(0xFFC62828);
    }
  }

  Widget _buildDynamicForm() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _isEditMode ? 'تعديل مطعم' : 'إنشاء مطعم جديد',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: burgundy,
                      ),
                    ),
                  ),
                  if (_isEditMode)
                    TextButton.icon(
                      onPressed: _saving ? null : _resetForm,
                      icon: const Icon(Icons.add_business_outlined),
                      label: const Text('مطعم جديد'),
                    ),
                ],
              ),
              if (_isEditMode && _editingRestaurant != null) ...[
                const SizedBox(height: 4),
                Text(
                  'المعرف: ${_editingRestaurant!.id}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF666666)),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'اسم المطعم *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _ownerController,
                decoration: const InputDecoration(
                  labelText: 'اسم المالك / المدير',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'رقم الهاتف الأساسي',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _slugController,
                decoration: const InputDecoration(
                  labelText: 'المعرف (slug) * — للرابط والدخول',
                  hintText: 'bait-amsha',
                  helperText: 'يُستخدم في رابط العملاء: /menu/slug',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<RestaurantStatus>(
                value: _status,
                decoration: const InputDecoration(
                  labelText: 'حالة المطعم',
                  border: OutlineInputBorder(),
                ),
                items: RestaurantStatus.values
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(value.labelAr),
                      ),
                    )
                    .toList(),
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() => _status = value);
                      },
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              const Text(
                'بيانات الاشتراك',
                style: TextStyle(fontWeight: FontWeight.bold, color: burgundy),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<SubscriptionPlan>(
                value: _subscriptionPlan,
                decoration: const InputDecoration(
                  labelText: 'خطة الاشتراك',
                  border: OutlineInputBorder(),
                ),
                items: SubscriptionPlan.values
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(value.labelAr),
                      ),
                    )
                    .toList(),
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() => _subscriptionPlan = value);
                      },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<SubscriptionStatus>(
                value: _subscriptionStatus,
                decoration: const InputDecoration(
                  labelText: 'حالة الاشتراك',
                  border: OutlineInputBorder(),
                ),
                items: SubscriptionStatus.values
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(value.labelAr),
                      ),
                    )
                    .toList(),
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() => _subscriptionStatus = value);
                      },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _subscriptionExpiryController,
                decoration: const InputDecoration(
                  labelText: 'تاريخ انتهاء الاشتراك (YYYY-MM-DD)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _subscriptionNotesController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات الاشتراك',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: _isEditMode
                      ? 'كلمة مرور مدير المطعم (اتركها فارغة للإبقاء)'
                      : 'كلمة مرور مدير المطعم *',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: burgundy),
                onPressed: _saving ? null : _saveRestaurant,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Icon(
                        _isEditMode ? Icons.save : Icons.add_business,
                        color: Colors.white,
                      ),
                label: Text(
                  _saving
                      ? 'جاري الحفظ...'
                      : (_isEditMode ? 'حفظ التعديلات' : 'إنشاء المطعم'),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRestaurantTile(Restaurant restaurant) {
    final menuPath = RestaurantRoute.menuPathForSlug(restaurant.slug);
    final menuUrl = kIsWeb ? '${Uri.base.origin}$menuPath' : menuPath;
    final selected = _editingRestaurant?.id == restaurant.id;

    return Card(
      color: selected ? const Color(0xFFFFF3F5) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? burgundy : Colors.grey.shade300,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _loadRestaurantIntoForm(restaurant),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.store, color: _statusColor(restaurant.status)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      restaurant.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text('slug: ${restaurant.slug}'),
                    if (restaurant.ownerName.isNotEmpty)
                      Text('المالك: ${restaurant.ownerName}'),
                    if (restaurant.phone.isNotEmpty)
                      Text('الهاتف: ${restaurant.phone}'),
                    Text('رابط العملاء: $menuUrl'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _badge(
                          restaurant.status.labelAr,
                          _statusColor(restaurant.status),
                        ),
                        _badge(
                          restaurant.subscriptionPlan.labelAr,
                          burgundy,
                        ),
                        _badge(
                          restaurant.subscriptionStatus.labelAr,
                          const Color(0xFF1565C0),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  IconButton(
                    tooltip: 'تعديل',
                    onPressed: () => _loadRestaurantIntoForm(restaurant),
                    icon: const Icon(Icons.edit_outlined, color: burgundy),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _importTalabatForRestaurant(restaurant),
                    icon: const Icon(Icons.cloud_download, size: 16),
                    label: const Text('Talabat'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'إدارة المطاعم — AlMenuPro',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: burgundy),
          ),
          const SizedBox(height: 8),
          const Text(
            'اضغط على أي مطعم لتعديل بياناته، أو أنشئ مطعماً جديداً من النموذج.',
          ),
          const SizedBox(height: 20),
          if (_storageHealth != null && !_storageHealth!.persistent)
            Card(
              color: const Color(0xFFFFEBEE),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Color(0xFFC62828)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'تحذير: التخزين الحالي (${_storageHealth!.storage}) غير دائم. '
                        'المطاعم الجديدة لن تُحفظ بعد تحديث الصفحة حتى تضيف '
                        'MONGODB_URI و MONGODB_DB في Vercel وتعيد نشر الباك إند.',
                        style: const TextStyle(color: Color(0xFF5D1A1A), height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_storageHealth != null && !_storageHealth!.persistent)
            const SizedBox(height: 16),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final useSideBySide = constraints.maxWidth >= 980;
                if (useSideBySide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 5,
                        child: _loading
                            ? const Center(
                                child: CircularProgressIndicator(color: burgundy),
                              )
                            : _errorMessage != null
                                ? Center(child: Text(_errorMessage!))
                                : ListView.separated(
                                    itemCount: _restaurants.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(height: 10),
                                    itemBuilder: (context, index) =>
                                        _buildRestaurantTile(_restaurants[index]),
                                  ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(flex: 6, child: _buildDynamicForm()),
                    ],
                  );
                }

                return ListView(
                  children: [
                    _buildDynamicForm(),
                    const SizedBox(height: 20),
                    if (_loading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(color: burgundy),
                        ),
                      )
                    else if (_errorMessage != null)
                      Center(child: Text(_errorMessage!))
                    else
                      ..._restaurants.map(_buildRestaurantTile),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
