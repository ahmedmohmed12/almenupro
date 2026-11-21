import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/table_qr_demo_catalog.dart';
import '../l10n/app_strings.dart';
import '../models/dining_table.dart';
import '../models/menu_item.dart';
import '../models/order.dart';
import '../providers/cart_provider.dart';
import '../providers/customer_session_provider.dart';
import '../providers/order_type_provider.dart';
import '../services/api_service.dart';
import '../services/dining_tables_service.dart';
import '../services/orders_service.dart';
import '../services/table_floor_live_service.dart';
import '../theme/app_theme.dart';
import '../utils/table_qr_route.dart';
import '../widgets/language_toggle_button.dart';
import '../widgets/table_qr/table_qr_category_nav.dart';
import '../widgets/table_qr/table_qr_customize_sheet.dart';
import '../widgets/table_qr/table_qr_floating_cart_bar.dart';
import '../widgets/table_qr/table_qr_header.dart';
import '../widgets/table_qr/table_qr_item_card.dart';
import '../widgets/table_qr/table_qr_order_summary_sheet.dart';
import '../widgets/table_qr/table_service_actions.dart';
import '../widgets/menu/video/menu_video_widgets.dart';

/// Frictionless QR table ordering — no login, phone, or address.
class TableQrOrderingScreen extends StatefulWidget {
  const TableQrOrderingScreen({
    super.key,
    this.branchId,
    this.tableId,
    this.restaurantId,
    this.tableName,
    this.zone,
    this.restaurantName,
    this.restaurantSlug,
    this.logoUrl,
    this.useDemoCatalog = false,
  });

  final String? branchId;
  final String? tableId;
  final String? restaurantId;
  final String? tableName;
  final String? zone;
  final String? restaurantName;
  final String? restaurantSlug;
  final String? logoUrl;
  final bool useDemoCatalog;

  @override
  State<TableQrOrderingScreen> createState() => _TableQrOrderingScreenState();
}

class _TableQrOrderingScreenState extends State<TableQrOrderingScreen> {
  final _categoryScroll = ScrollController();
  final _itemScroll = ScrollController();
  final Map<String, GlobalKey> _categoryKeys = {};

  var _loading = true;
  var _busyWaiter = false;
  String? _error;
  var _usingDemo = false;

  String _branchId = '';
  String _tableId = '';
  String _restaurantId = '';
  String _tableName = '';
  String _zone = '';
  String _restaurantName = '';
  String _restaurantSlug = '';
  String _logoUrl = '';

  List<MenuItem> _items = const [];
  List<String> _categories = const [];
  String _selectedCategory = '';
  DiningTable? _table;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_bootstrap());
    });
  }

  @override
  void dispose() {
    _categoryScroll.dispose();
    _itemScroll.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final fromUrl = TableQrRouteParams.fromBrowser();
    _branchId = (widget.branchId ?? fromUrl?.branchId ?? '').trim();
    _tableId = (widget.tableId ?? fromUrl?.tableId ?? '').trim();
    _restaurantId = (widget.restaurantId ?? fromUrl?.restaurantId ?? '').trim();
    _tableName = (widget.tableName ?? '').trim();
    _zone = (widget.zone ?? '').trim();
    _restaurantName = (widget.restaurantName ?? '').trim();
    _restaurantSlug = (widget.restaurantSlug ?? fromUrl?.slug ?? '').trim();
    _logoUrl = (widget.logoUrl ?? '').trim();

    if (_tableId.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Missing table id in URL (table / table_id).';
      });
      return;
    }

    if (_branchId.isEmpty) {
      _branchId = _restaurantId;
    }
    if (_restaurantId.isEmpty) {
      _restaurantId = _branchId;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (!widget.useDemoCatalog &&
          _branchId.isNotEmpty &&
          _tableId.isNotEmpty) {
        try {
          final result = await DiningTablesService.instance.fetchPublicTable(
            branchId: _branchId,
            tableId: _tableId,
          );
          _table = result.table;
          _tableId = result.table.id;
          _tableName = result.table.displayName;
          _zone = result.table.zone;
          _restaurantName =
              result.restaurant['name']?.toString() ?? _restaurantName;
          _restaurantId =
              result.restaurant['id']?.toString() ??
              _restaurantId;
          _restaurantSlug =
              result.restaurant['slug']?.toString() ??
              _restaurantSlug;
          _logoUrl =
              result.restaurant['logoUrl']?.toString() ??
              result.restaurant['logo_url']?.toString() ??
              _logoUrl;
        } catch (_) {
          // Fall through to catalog load with provided ids.
        }
      }

      if (_restaurantName.isEmpty) {
        _restaurantName = TableQrDemoCatalog.restaurantName;
      }
      if (_tableName.isEmpty) {
        _tableName = 'طاولة $_tableId';
      }
      if (_zone.isEmpty) {
        _zone = 'الصالة الرئيسية';
      }

      _bindSession();

      if (widget.useDemoCatalog) {
        _applyCatalog(TableQrDemoCatalog.items(), demo: true);
      } else {
        await _loadMenu();
      }
    } catch (error) {
      if (!mounted) return;
      _applyCatalog(TableQrDemoCatalog.items(), demo: true);
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _bindSession() {
    context.read<CustomerSessionProvider>().bindDineInTable(
      tableId: _tableId,
      tableName: _tableName,
      restaurantId: _restaurantId.isNotEmpty ? _restaurantId : _branchId,
      tableZone: _zone,
    );
    context.read<OrderTypeProvider>().setOrderType(OrderType.dineIn);
    final restaurantId =
        _restaurantId.isNotEmpty ? _restaurantId : _branchId;
    if (restaurantId.isNotEmpty) {
      context.read<CartProvider>().bindRestaurant(restaurantId);
    }
  }

  Future<void> _loadMenu() async {
    final restaurantId =
        _restaurantId.isNotEmpty ? _restaurantId : _branchId;
    try {
      List<MenuItem> items = const [];
      if (_restaurantSlug.isNotEmpty) {
        items = await ApiService.instance.fetchPublicItems(
          slug: _restaurantSlug,
        );
      } else if (restaurantId.isNotEmpty) {
        items = await ApiService.instance.fetchPublicItems(
          restaurantId: restaurantId,
        );
      }
      if (items.isEmpty) {
        _applyCatalog(TableQrDemoCatalog.items(), demo: true);
        return;
      }
      _applyCatalog(items, demo: false);

      try {
        if (_restaurantSlug.isNotEmpty || restaurantId.isNotEmpty) {
          final restaurant = await ApiService.instance.fetchPublicRestaurant(
            slug: _restaurantSlug.isNotEmpty ? _restaurantSlug : null,
            restaurantId:
                _restaurantSlug.isEmpty ? restaurantId : null,
          );
          if (!mounted) return;
          setState(() {
            if (_restaurantName.isEmpty) {
              _restaurantName = restaurant.name;
            }
            _restaurantId = restaurant.id;
          });
        }
      } catch (_) {}
    } catch (_) {
      _applyCatalog(TableQrDemoCatalog.items(), demo: true);
    }
  }

  void _applyCatalog(List<MenuItem> items, {required bool demo}) {
    final available =
        items.where((item) => item.isAvailable).toList(growable: false);
    final categories = <String>[];
    for (final item in available) {
      final name = item.categoryName.trim().isEmpty
          ? 'أخرى'
          : item.categoryName.trim();
      if (!categories.contains(name)) categories.add(name);
    }
    for (final category in categories) {
      _categoryKeys.putIfAbsent(category, GlobalKey.new);
    }
    setState(() {
      _items = available;
      _categories = categories;
      _selectedCategory = categories.isEmpty ? '' : categories.first;
      _usingDemo = demo;
      _loading = false;
    });
  }

  String get _tableBadge {
    final padded = _tableName.trim().isNotEmpty
        ? _tableName
        : 'طاولة ${_tableId.padLeft(2, '0')}';
    return padded;
  }

  List<MenuItem> get _visibleItems {
    if (_selectedCategory.isEmpty) return _items;
    return _items
        .where((item) {
          final name = item.categoryName.trim().isEmpty
              ? 'أخرى'
              : item.categoryName.trim();
          return name == _selectedCategory;
        })
        .toList();
  }

  void _onCategorySelected(String category) {
    setState(() => _selectedCategory = category);
    final key = _categoryKeys[category];
    final ctx = key?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 280),
        alignment: 0.5,
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _openCustomize(MenuItem item) {
    return showTableQrCustomizeSheet(context, item);
  }

  void _quickAdd(MenuItem item) {
    if (_table?.isAwaitingCheck == true) {
      _showAwaitingCheckLock();
      return;
    }
    if (tableQrHasMandatoryOptions(item)) {
      unawaited(_openCustomize(item));
      return;
    }
    context.read<CartProvider>().addMenuItem(item);
    final strings = AppStrings.read(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          strings.addedToCart(item.localizedName(strings.localeCode)),
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _showAwaitingCheckLock() {
    final strings = AppStrings.read(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          strings.tr(
            'تم طلب الحساب ولا يمكن إضافة أصناف جديدة',
            'The bill was requested; new items cannot be added',
          ),
        ),
      ),
    );
  }

  Future<void> _callWaiter() async {
    final strings = AppStrings.read(context);
    if (_branchId.isEmpty || _tableId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            strings.tr(
              'تم تسجيل نداء الويتر (تجريبي)',
              'Waiter call recorded (demo)',
            ),
          ),
          backgroundColor: const Color(0xFF3B82F6),
        ),
      );
      return;
    }
    setState(() => _busyWaiter = true);
    try {
      final table = await DiningTablesService.instance.callWaiterPublic(
        branchId: _branchId,
        tableId: _tableId,
        note: '',
      );
      final restaurantId =
          _restaurantId.isNotEmpty ? _restaurantId : _branchId;
      unawaited(TableFloorLiveService.instance.publish(table, restaurantId));
      if (!mounted) return;
      setState(() => _table = table);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF3B82F6),
          content: Text(
            strings.tr(
              'تم إرسال طلب الويتر إلى الصالة',
              'The waiter request was sent',
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _busyWaiter = false);
    }
  }

  Future<void> _openSummary() async {
    if (_table?.isAwaitingCheck == true) {
      _showAwaitingCheckLock();
      return;
    }
    final result = await showTableQrOrderSummarySheet(
      context: context,
      tableLabel: _zone.isEmpty ? _tableBadge : '$_tableBadge - $_zone',
      onSendToKitchen: _sendToKitchen,
    );
    if (result == 'sent' && mounted) {
      final strings = AppStrings.read(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade700,
          content: Text(
            strings.tr(
              'تم إرسال الطلب إلى المطبخ',
              'Order sent to the kitchen',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _sendToKitchen(String kitchenNotes) async {
    final cart = context.read<CartProvider>();
    if (cart.isEmpty) {
      throw Exception('السلة فارغة');
    }
    if (_usingDemo || widget.useDemoCatalog) {
      throw Exception(
        'وضع تجريبي — لا يُرسل الطلب للمطبخ. افتح رابط QR الصحيح أو حمّل منيو المطعم الحقيقي.',
      );
    }
    if (_branchId.isEmpty || _tableId.isEmpty) {
      throw Exception(
        'معرّف الطاولة أو الفرع غير مكتمل — لا يمكن إرسال طلب حقيقي.',
      );
    }
    if (_table?.isAwaitingCheck == true) {
      throw Exception('تم طلب الحساب ولا يمكن إرسال طلب جديد');
    }

    final session = context.read<CustomerSessionProvider>();
    final tableId = session.dineInTableId ?? _tableId;
    final tableName = session.dineInTableName ?? _tableName;
    final restaurantId =
        session.dineInRestaurantId ??
        (_restaurantId.isNotEmpty ? _restaurantId : _branchId);

    final invoiceNumber =
        DateTime.now().millisecondsSinceEpoch.toString().substring(5);
    final addressParts = <String>[
      tableName.isEmpty ? 'طاولة QR' : tableName,
      if (_zone.trim().isNotEmpty) _zone.trim(),
      if (kitchenNotes.trim().isNotEmpty) 'ملاحظات: ${kitchenNotes.trim()}',
    ];

    await OrdersService.instance.submitOrderFromCart(
      cartItems: List.from(cart.items),
      customerName: tableName.isEmpty ? 'طاولة $tableId' : tableName,
      phone: '00000000',
      address: addressParts.join(' · '),
      paymentMethod: 'cash',
      invoiceNumber: invoiceNumber,
      restaurantId: restaurantId,
      deliveryFee: 0,
      orderSource: 'qr-dine-in',
      orderType: OrderType.dineIn,
      tableId: tableId,
      refreshList: false,
    );

    cart.clear();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final cart = context.watch<CartProvider>();

    return Scaffold(
      backgroundColor: AppTheme.brandBackground,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                TableQrHeader(
                  restaurantName: _restaurantName,
                  logoUrl: _logoUrl,
                  tableLabel: _tableBadge,
                  zoneLabel: _zone,
                  busy: _busyWaiter,
                  onCallWaiter: _callWaiter,
                ),
                FeaturedStoriesBar(items: _items, onAdd: _quickAdd),
                if (_usingDemo || (_error != null && _items.isNotEmpty))
                  Material(
                    color: const Color(0xFFFFF4E5),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline,
                            size: 18,
                            color: AppTheme.brandOrange,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              strings.tr(
                                'عرض تجريبي للمنيو — للمعاينة فقط (لا يُرسل للمطبخ)',
                                'Demo menu preview — display only (not sent to kitchen)',
                              ),
                              style: const TextStyle(fontSize: 12.5),
                            ),
                          ),
                          const LanguageToggleButton(),
                        ],
                      ),
                    ),
                  )
                else
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8, top: 4),
                      child: LanguageToggleButton(),
                    ),
                  ),
                if (_error != null && _items.isEmpty)
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!, textAlign: TextAlign.center),
                      ),
                    ),
                  )
                else ...[
                  if (_categories.isNotEmpty)
                    TableQrCategoryNav(
                      categories: _categories,
                      selected: _selectedCategory,
                      onSelected: _onCategorySelected,
                      scrollController: _categoryScroll,
                    ),
                  Expanded(
                    child: ListView.separated(
                      controller: _itemScroll,
                      padding: EdgeInsets.fromLTRB(
                        14,
                        8,
                        14,
                        cart.itemCount > 0 ? 100 : 24,
                      ),
                      itemCount: _visibleItems.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final item = _visibleItems[index];
                        final category = item.categoryName.trim().isEmpty
                            ? 'أخرى'
                            : item.categoryName.trim();
                        final key = index == 0
                            ? _categoryKeys[category]
                            : null;
                        return KeyedSubtree(
                          key: key,
                          child: TableQrItemCard(
                            item: item,
                            onOpenDetails: () {
                              if (_table?.isAwaitingCheck == true) {
                                _showAwaitingCheckLock();
                                return;
                              }
                              unawaited(_openCustomize(item));
                            },
                            onQuickAdd: () => _quickAdd(item),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
      bottomNavigationBar: TableQrFloatingCartBar(
        itemCount: cart.itemCount,
        totalPrice: cart.totalPrice,
        onCheckout: _openSummary,
      ),
      floatingActionButton: TableServiceActions(
        branchId: _branchId,
        tableId: _tableId,
        restaurantId: _restaurantId.isNotEmpty
            ? _restaurantId
            : _branchId,
        onTableChanged: (table) => setState(() => _table = table),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}

/// Opens the dedicated table ordering page from a portal or deep link.
void openTableQrOrdering(
  BuildContext context, {
  required String branchId,
  required String tableId,
  String? restaurantId,
  String? tableName,
  String? zone,
  String? restaurantName,
  String? restaurantSlug,
  String? logoUrl,
}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => TableQrOrderingScreen(
        branchId: branchId,
        tableId: tableId,
        restaurantId: restaurantId,
        tableName: tableName,
        zone: zone,
        restaurantName: restaurantName,
        restaurantSlug: restaurantSlug,
        logoUrl: logoUrl,
      ),
    ),
  );
}
