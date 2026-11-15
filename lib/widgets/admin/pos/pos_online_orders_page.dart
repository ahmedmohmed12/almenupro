import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_strings.dart';
import '../../../models/order.dart';
import '../../../models/pos_role.dart';
import '../../../models/sales_platform_config.dart';
import '../../../services/admin_auth_service.dart';
import '../../../services/admin_order_focus_service.dart';
import '../../../services/admin_order_monitor_service.dart';
import '../../../services/incoming_order_auto_accept_service.dart';
import '../../../services/orders_service.dart';
import '../../../services/platform_directory_refresh.dart';
import '../../../services/platform_today_sync.dart';
import '../../../services/api_service.dart';
import '../../../services/pos_operations_service.dart';
import '../../../services/restaurant_settings_service.dart';
import '../../../utils/admin_deep_link.dart';
import '../../../utils/order_channel_utils.dart';
import '../admin_corner_toast.dart';
import '../platform_today_sync_button.dart';
import '../admin_order_details_dialog.dart';
import '../order_inbox_search_field.dart';
import '../scheduled_invoice_list.dart';
import '../incoming_order_countdown_badge.dart';
import '../order_status_chip.dart';
import '../order_driver_tracking_card.dart';
import '../driver_handshake_banners.dart';
import 'pos_driver_handoff_page.dart';
import '../../../services/delivery_dispatch_service.dart';

/// Incoming online / QR menu orders for the active cashier shift.
class PosOnlineOrdersPage extends StatefulWidget {
  const PosOnlineOrdersPage({
    super.key,
    this.showPageHeader = true,
    this.tableManagementEnabled = false,
  });

  final bool showPageHeader;
  final bool tableManagementEnabled;

  @override
  State<PosOnlineOrdersPage> createState() => _PosOnlineOrdersPageState();
}

class _PosOnlineOrdersPageState extends State<PosOnlineOrdersPage>
    with SingleTickerProviderStateMixin {
  static const burgundy = Color(0xFF6B1124);

  final _ordersService = OrdersService.instance;
  final _monitor = AdminOrderMonitorService.instance;
  List<SalesPlatformConfig> _platforms = SalesPlatformConfig.defaults();
  var _processingId = '';
  late final TabController _tabController;
  final _searchController = TextEditingController();
  var _searchQuery = '';
  var _openingFocusedOrder = false;
  String? _openedFocusRef;
  late final void Function() _stopBackgroundSync;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _tabCount(widget.tableManagementEnabled),
      vsync: this,
    );
    _searchController.addListener(_onSearchChanged);
    AdminOrderFocusService.instance.addListener(_onOrderFocusChanged);
    PlatformDirectoryRefresh.tick.addListener(_onDirectoryRefresh);
    _stopBackgroundSync = listenPlatformSyncResult(_onBackgroundCapture);
    unawaited(_loadPlatforms());
    unawaited(_ordersService.refreshOrders());
    DeliveryBoardController.instance.ensureStarted();
  }

  @override
  void didUpdateWidget(covariant PosOnlineOrdersPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tableManagementEnabled != widget.tableManagementEnabled) {
      final index = _tabController.index;
      _tabController.dispose();
      _tabController = TabController(
        length: _tabCount(widget.tableManagementEnabled),
        vsync: this,
        initialIndex: index.clamp(
          0,
          _tabCount(widget.tableManagementEnabled) - 1,
        ),
      );
    }
  }

  @override
  void dispose() {
    AdminOrderFocusService.instance.removeListener(_onOrderFocusChanged);
    PlatformDirectoryRefresh.tick.removeListener(_onDirectoryRefresh);
    _stopBackgroundSync();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final next = _searchController.text;
    if (next == _searchQuery || !mounted) return;
    setState(() => _searchQuery = next);
  }

  void _onOrderFocusChanged() {
    if (mounted) setState(() {});
  }

  void _onDirectoryRefresh() {
    unawaited(_ordersService.refreshOrders());
  }

  void _onBackgroundCapture(PlatformSyncDetail detail) {
    if (detail.synced <= 0 && detail.purged <= 0) return;
    unawaited(_ordersService.refreshOrders());
    PlatformDirectoryRefresh.notify();
    if (!mounted || !detail.background || detail.notice.isEmpty) return;
    AdminCornerToast.show(
      context,
      detail.notice,
      backgroundColor: const Color(0xFF166534),
      maxWidth: 520,
      duration: const Duration(seconds: 6),
    );
  }

  void _tryOpenFocusedOrder(List<Order> orders) {
    if (!mounted || _openingFocusedOrder || orders.isEmpty) return;
    final ref = AdminOrderFocusService.instance.pendingOrderRef;
    if (ref == null || ref.isEmpty) return;
    if (_openedFocusRef == ref) return;

    Order? match;
    for (final order in orders) {
      if (AdminDeepLink.matchesOrder(
        ref,
        id: order.id,
        invoiceNumber: order.invoiceNumber,
      )) {
        match = order;
        break;
      }
    }
    if (match == null) return;

    _openedFocusRef = ref;
    AdminOrderFocusService.instance.consumeOrder();
    IncomingOrderAutoAcceptService.instance.focusDeepLinkedOrder(match);
    if (match.needsCashierHandoff || match.waitingDriverAfterCashierConfirm) {
      _tabController.animateTo(_tabIndex('handoff'));
    } else {
      _tabController.animateTo(_tabIndexFor(match));
    }
    _openingFocusedOrder = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _openingFocusedOrder = false;
        return;
      }
      try {
        await _openDetails(match!);
      } finally {
        _openingFocusedOrder = false;
      }
    });
  }

  Future<void> _loadPlatforms() async {
    try {
      final settings = await RestaurantSettingsService.instance.load();
      if (!mounted) return;
      setState(() => _platforms = settings.resolvedSalesPlatforms);
    } catch (_) {}
  }

  bool get _canProcess => PosOperationsService.instance.allows(
    PosPermissionKeys.receiveOnlineOrders,
  );

  bool _belongsToCashier(Order order) {
    final session = PosOperationsService.instance.cashierSession;
    final shift = PosOperationsService.instance.activeShift;
    final cashierId = (session?.staff.id ?? shift?.cashierId ?? '').trim();
    final shiftId = (shift?.id ?? '').trim();
    final cashierName = (session?.staff.name ?? shift?.cashierName ?? '')
        .trim()
        .toLowerCase();

    final orderCashierId = (order.cashierId ?? '').trim();
    final orderShiftId = (order.shiftId ?? '').trim();
    final orderCashierName = order.receivedByCashierLabel.trim().toLowerCase();

    if (orderCashierId.isNotEmpty &&
        cashierId.isNotEmpty &&
        orderCashierId == cashierId) {
      return true;
    }
    if (orderShiftId.isNotEmpty &&
        shiftId.isNotEmpty &&
        orderShiftId == shiftId) {
      return true;
    }
    if (orderCashierName.isNotEmpty &&
        cashierName.isNotEmpty &&
        orderCashierName == cashierName) {
      return true;
    }
    return false;
  }

  bool _isUnassignedOnlineOrder(Order order) {
    if (!isOnlineMenuOrder(order)) return false;
    return (order.cashierId ?? '').trim().isEmpty &&
        (order.shiftId ?? '').trim().isEmpty &&
        order.receivedByCashierLabel.trim().isEmpty;
  }

  bool _visibleToCashier(Order order) =>
      _belongsToCashier(order) || _isUnassignedOnlineOrder(order);

  int _tabCount(bool hall) =>
      orderInboxTabKeys(hall: hall, handoff: true).length;

  int _tabIndex(String key) {
    final keys = orderInboxTabKeys(
      hall: widget.tableManagementEnabled,
      handoff: true,
    );
    final index = keys.indexOf(key);
    if (index < 0) return keys.indexOf('previous').clamp(0, keys.length - 1);
    return index;
  }

  int _tabIndexFor(Order order) {
    if (order.status == OrderStatus.scheduled) return _tabIndex('scheduled');
    if (order.status == OrderStatus.pending || order.isNewForCashier) {
      return _tabIndex('new');
    }
    if (order.isCurrentForCashier) return _tabIndex('current');
    final channel = inboxChannelKey(order);
    if (channel == 'hall' && !widget.tableManagementEnabled) {
      return _tabIndex('previous');
    }
    return _tabIndex(channel);
  }

  Widget _cashierChannelList(
    AppStrings s,
    DateFormat dateFormat,
    List<Order> orders,
    String emptyTitle,
    String emptyEnglish, {
    String? emptySubtitle,
    String? emptySubtitleEnglish,
  }) {
    return _PosOnlineOrdersList(
      orders: orders,
      dateFormat: dateFormat,
      platforms: _platforms,
      processingId: _processingId,
      emptyTitle: _searchQuery.trim().isEmpty
          ? s.tr(emptyTitle, emptyEnglish)
          : s.tr('لا توجد نتائج لهذا البحث', 'No orders match this search'),
      emptySubtitle: s.tr(
        emptySubtitle ??
            'تظهر هنا بعد ما تخرج من طلب جديد: الحالية والمنتهية لهذه القناة.',
        emptySubtitleEnglish ??
            'Current and finished orders for this channel appear here after they leave New.',
      ),
      onOpen: _openDetails,
      onNextStatus: _updateMineStatus,
      onHandoffConfirm: _confirmHandoff,
      showDriverTracking: true,
    );
  }

  List<Order> _cashierSourceOrders(
    Iterable<Order> orders,
    bool Function(Order order) test,
  ) {
    return ordersForSource(
      orders.where(
        (order) => isCashierMenuOrder(order) && _visibleToCashier(order),
      ),
      test,
    );
  }

  List<Order> _platformHistoryOrders(
    Iterable<Order> orders,
    bool Function(Order order) test,
  ) {
    return ordersForPlatform(orders.where(isCashierMenuOrder), test);
  }

  ({String cashierId, String cashierName, String shiftId})
  get _receivingIdentity {
    final shift = PosOperationsService.instance.activeShift;
    final cashier = PosOperationsService.instance.cashierSession;
    final staffId = cashier?.staff.id.trim() ?? '';
    final staffName = cashier?.staff.name.trim() ?? '';
    final shiftCashierId = shift?.cashierId.trim() ?? '';
    final shiftCashierName = shift?.cashierName.trim() ?? '';
    final sessionName =
        AdminAuthService.instance.session?.staffName?.trim() ?? '';
    final sessionId = AdminAuthService.instance.session?.staffId?.trim() ?? '';
    final cashierId = [
      staffId,
      shiftCashierId,
      sessionId,
    ].firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final cashierName = [
      staffName,
      shiftCashierName,
      sessionName,
    ].firstWhere((value) => value.isNotEmpty, orElse: () => 'كاشير');
    return (
      cashierId: cashierId,
      cashierName: cashierName,
      shiftId: shift?.id.trim() ?? '',
    );
  }

  Future<void> _updateMineStatus(Order order, OrderStatus status) async {
    if (order.isHeldByDriver) {
      AdminCornerToast.error(context, Order.driverCustodyLockMessage);
      return;
    }
    setState(() => _processingId = order.id);
    try {
      final identity = _receivingIdentity;
      await _ordersService.updateOrderStatus(
        order.id,
        status,
        shiftId: identity.shiftId.isNotEmpty ? identity.shiftId : order.shiftId,
        cashierId: identity.cashierId.isNotEmpty
            ? identity.cashierId
            : order.cashierId,
        cashierName: identity.cashierName.isNotEmpty
            ? identity.cashierName
            : order.cashierName,
      );
      if (!mounted) return;
      if (status == OrderStatus.delivered) {
        final channel = inboxChannelKey(order);
        final tabKey = channel == 'hall' && !widget.tableManagementEnabled
            ? 'previous'
            : channel;
        _tabController.animateTo(_tabIndex(tabKey));
        AdminCornerToast.success(
          context,
          channel == 'hall'
              ? 'تم تسكير حساب الطاولة — يظهر في طاولات الصالة'
              : 'تم التوصيل — الطلب انتقل لتبويب مصدره',
        );
      } else if (status == OrderStatus.preparing) {
        AdminCornerToast.success(context, 'الطلب في الطريق');
      } else {
        AdminCornerToast.success(context, 'تم تحديث حالة الطلب');
      }
    } catch (error) {
      if (!mounted) return;
      AdminCornerToast.error(
        context,
        error.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) setState(() => _processingId = '');
    }
  }

  Future<void> _confirmHandoff(Order order) async {
    final requestId = (order.deliveryRequestId ?? '').trim().isNotEmpty
        ? order.deliveryRequestId!.trim()
        : (DeliveryBoardController.instance.requestForOrder(order.id)?.id ??
              '');
    if (requestId.isEmpty) {
      AdminCornerToast.error(context, 'لا يوجد طلب توصيل مرتبط');
      return;
    }
    setState(() => _processingId = order.id);
    try {
      await ApiService.instance.postDeliveryAction(
        requestId,
        'cashier-confirm',
      );
      await _ordersService.refreshOrders();
      if (!mounted) return;
      AdminCornerToast.success(context, 'تم تسجيل تأكيدك المالي');
    } catch (error) {
      if (!mounted) return;
      AdminCornerToast.error(
        context,
        error.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) setState(() => _processingId = '');
    }
  }

  Future<void> _openDetails(Order order) async {
    await showAdminOrderDetailsDialog(
      context,
      order: order,
      platforms: _platforms,
      showStatusActions: !order.isHeldByDriver,
      onStatusChanged: (orderId, status) async {
        if (order.status == OrderStatus.pending &&
            status == OrderStatus.confirmed) {
          await _acceptOrder(order);
          return;
        }
        await _updateMineStatus(order, status);
      },
    );
  }

  Future<void> _acceptOrder(Order order) async {
    if (!_canProcess) {
      AdminCornerToast.error(context, 'لا تملك صلاحية معالجة الطلبات');
      return;
    }

    final activeShift = PosOperationsService.instance.activeShift;
    if (activeShift == null || !activeShift.isOpen) {
      AdminCornerToast.error(context, 'افتح وردية POS قبل قبول طلبات المنيو');
      return;
    }

    setState(() => _processingId = order.id);

    try {
      await IncomingOrderAutoAcceptService.instance.acceptManually(order);

      if (!mounted) return;

      AdminCornerToast.success(
        context,
        order.orderType == OrderType.delivery
            ? 'تم قبول الطلب وتعيينه للسائق — يظهر في قائمة جديد لدى السائق'
            : 'تم قبول الطلب — يظهر الآن في شاشة المطبخ ويُحسب في ورديتك',
      );
      if (order.orderType != OrderType.delivery) {
        _tabController.animateTo(1);
      }
    } catch (error) {
      if (!mounted) return;
      AdminCornerToast.error(
        context,
        error.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) setState(() => _processingId = '');
    }
  }

  Future<void> _rejectOrder(Order order) async {
    final s = AppStrings.read(context);
    if (!_canProcess) {
      AdminCornerToast.error(
        context,
        s.tr('لا تملك صلاحية معالجة الطلبات', 'You cannot process orders'),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.tr('رفض الطلب', 'Reject order')),
        content: Text(
          s.tr(
            'هل تريد رفض طلب ${order.customerName} (${order.totalPrice.toStringAsFixed(3)} د.ك)؟',
            'Reject ${order.customerName}’s order (${order.totalPrice.toStringAsFixed(3)} KWD)?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.tr('تراجع', 'Back')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.tr('رفض', 'Reject')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _processingId = order.id);
    IncomingOrderAutoAcceptService.instance.cancel(order.id);
    await _monitor.acknowledgeOrder(order.id);

    try {
      await _ordersService.updateOrderStatus(order.id, OrderStatus.cancelled);
      if (!mounted) return;
      AdminCornerToast.success(context, s.tr('تم رفض الطلب', 'Order rejected'));
    } catch (error) {
      if (!mounted) return;
      AdminCornerToast.error(
        context,
        s.tr('تعذر رفض الطلب', 'Could not reject order'),
      );
    } finally {
      if (mounted) setState(() => _processingId = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final dateFormat = DateFormat('d/M • HH:mm');

    return ColoredBox(
      color: const Color(0xFFF4F6F8),
      child: ListenableBuilder(
        listenable: PosOperationsService.instance,
        builder: (context, _) {
          return StreamBuilder<List<Order>>(
            stream: _ordersService.watchOrders(),
            initialData: const [],
            builder: (context, snapshot) {
              final orders = withoutScheduledHolds(snapshot.data ?? []);
              final scheduledOrders = filterOrdersByInboxQuery(
                scheduledHoldOrders(snapshot.data ?? []),
                _searchQuery,
              );
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _tryOpenFocusedOrder(snapshot.data ?? []);
              });
              final pendingOnline =
                  orders
                      .where(
                        (order) =>
                            !isClosedHallTableOrder(order) &&
                            isCashierMenuOrder(order) &&
                            (order.status == OrderStatus.pending ||
                                (order.status == OrderStatus.confirmed &&
                                    _isUnassignedOnlineOrder(order)) ||
                                (order.isWaitingDriver &&
                                    _belongsToCashier(order))),
                      )
                      .toList()
                    ..sort(compareOrdersByPlatformTimeDesc);
              final currentMine =
                  orders
                      .where(
                        (order) =>
                            !isClosedHallTableOrder(order) &&
                            isCashierMenuOrder(order) &&
                            order.isCurrentForCashier &&
                            order.status != OrderStatus.confirmed &&
                            (_belongsToCashier(order) ||
                                _isUnassignedOnlineOrder(order)),
                      )
                      .toList()
                    ..sort(compareOrdersByPlatformTimeDesc);
              final previousMine =
                  orders
                      .where(
                        (order) =>
                            isCashierMenuOrder(order) &&
                            order.status.isArchivedForAdmin &&
                            isLocalPosOrder(order) &&
                            _visibleToCashier(order) &&
                            !(widget.tableManagementEnabled &&
                                isClosedHallTableOrder(order)),
                      )
                      .toList()
                    ..sort(compareOrdersByPlatformTimeDesc);
              final talabatOrders = filterOrdersByInboxQuery(
                _platformHistoryOrders(orders, isTalabatOrder),
                _searchQuery,
              );
              final keetaOrders = filterOrdersByInboxQuery(
                _platformHistoryOrders(orders, isKeetaOrder),
                _searchQuery,
              );
              final jahezOrders = filterOrdersByInboxQuery(
                _platformHistoryOrders(orders, isJahezOrder),
                _searchQuery,
              );
              final websiteOrders = filterOrdersByInboxQuery(
                _cashierSourceOrders(orders, isWebsiteOrder),
                _searchQuery,
              );
              final hallTables = widget.tableManagementEnabled
                  ? filterOrdersByInboxQuery(
                      _cashierSourceOrders(orders, isHallTableOrder),
                      _searchQuery,
                    )
                  : <Order>[];
              final visiblePending = filterOrdersByInboxQuery(
                pendingOnline,
                _searchQuery,
              );
              final visibleCurrent = filterOrdersByInboxQuery(
                currentMine,
                _searchQuery,
              );
              final visiblePrevious = filterOrdersByInboxQuery(
                previousMine,
                _searchQuery,
              );
              final handoffQueue = orders
                  .where(
                    (order) =>
                        order.needsCashierHandoff ||
                        order.waitingDriverAfterCashierConfirm,
                  )
                  .toList();

              final shift = PosOperationsService.instance.activeShift;
              final onlineCashBound = shift?.cashCollected ?? 0;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.showPageHeader)
                    _OnlineOrdersHeader(
                      pendingCount: visiblePending.length,
                      currentCount: visibleCurrent.length,
                      previousCount: visiblePrevious.length,
                      shiftOpen: shift?.isOpen == true,
                      onlineCashBound: onlineCashBound,
                      expectedCash: shift?.summary.expectedCash ?? 0,
                      cashierName:
                          PosOperationsService
                              .instance
                              .cashierSession
                              ?.staff
                              .name ??
                          shift?.cashierName ??
                          '',
                    ),
                  if (!_canProcess)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: _PermissionBanner(),
                    ),
                  if (shift == null || !shift.isOpen)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: _ShiftRequiredBanner(),
                    ),
                  OrderInboxSearchField(
                    controller: _searchController,
                    onChanged: (_) => _onSearchChanged(),
                  ),
                  Material(
                    color: Colors.white,
                    child: TabBar(
                      controller: _tabController,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      labelColor: burgundy,
                      unselectedLabelColor: Colors.grey.shade600,
                      indicatorColor: const Color(0xFFD49A00),
                      indicatorWeight: 3,
                      tabs: [
                        Tab(
                          text:
                              '${s.tr('طلب جديد', 'New')} (${visiblePending.length})',
                        ),
                        Tab(
                          text:
                              '${s.tr('طلبات حالية', 'Current')} (${visibleCurrent.length})',
                        ),
                        Tab(
                          text:
                              '${s.tr('مجدولة', 'Scheduled')} (${scheduledOrders.length})',
                        ),
                        Tab(text: 'طلبات (${talabatOrders.length})'),
                        Tab(text: 'كيتا (${keetaOrders.length})'),
                        Tab(text: 'جاهز (${jahezOrders.length})'),
                        Tab(
                          text:
                              '${s.tr('طلبات الموقع', 'Website')} (${websiteOrders.length})',
                        ),
                        if (widget.tableManagementEnabled)
                          Tab(
                            text:
                                '${s.tr('طاولات الصالة', 'Dining tables')} (${hallTables.length})',
                          ),
                        Tab(
                          text:
                              '${s.tr('محلي سابق', 'Local archive')} (${visiblePrevious.length})',
                        ),
                        Tab(
                          text:
                              '${s.tr('صندوق السائق', 'Driver cash')} (${handoffQueue.length})',
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _PosOnlineOrdersList(
                          orders: visiblePending,
                          dateFormat: dateFormat,
                          platforms: _platforms,
                          processingId: _processingId,
                          emptyTitle: s.tr(
                            'لا توجد طلبات جديدة',
                            'No new orders',
                          ),
                          emptySubtitle: s.tr(
                            'أول ما يوصل الطلب من أي منصة أو الموقع أو الصالة يظهر هنا.',
                            'A new order from any platform, the website, or the hall appears here first.',
                          ),
                          onAccept: _acceptOrder,
                          onReject: _rejectOrder,
                          onOpen: _openDetails,
                        ),
                        _PosOnlineOrdersList(
                          orders: visibleCurrent,
                          dateFormat: dateFormat,
                          platforms: _platforms,
                          processingId: _processingId,
                          emptyTitle: s.tr(
                            'لا توجد طلبات حالية في حسابك',
                            'No current orders in your account',
                          ),
                          emptySubtitle: s.tr(
                            'بعد طلب جديد ينتقل هنا، ثم يبقى ظاهرًا في تبويب منصته.',
                            'After New, the order moves here and stays listed under its platform.',
                          ),
                          onOpen: _openDetails,
                          onNextStatus: _updateMineStatus,
                          onHandoffConfirm: _confirmHandoff,
                          showDriverTracking: true,
                        ),
                        ScheduledInvoiceList(orders: scheduledOrders),
                        _cashierChannelList(
                          s,
                          dateFormat,
                          talabatOrders,
                          'لا توجد فواتير طلبات',
                          'No Talabat orders',
                          emptySubtitle:
                              'كل فواتير طلبات المحفوظة من بداية التشغيل حتى اليوم.',
                          emptySubtitleEnglish:
                              'Every saved Talabat invoice from launch through today.',
                        ),
                        _cashierChannelList(
                          s,
                          dateFormat,
                          keetaOrders,
                          'لا توجد طلبات كيتا',
                          'No Keeta orders',
                          emptySubtitle:
                              'كل فواتير كيتا المحفوظة من بداية التشغيل حتى اليوم.',
                          emptySubtitleEnglish:
                              'Every saved Keeta invoice from launch through today.',
                        ),
                        _cashierChannelList(
                          s,
                          dateFormat,
                          jahezOrders,
                          'لا توجد طلبات جاهز',
                          'No Jahez orders',
                          emptySubtitle:
                              'كل فواتير جاهز المحفوظة من بداية التشغيل حتى اليوم.',
                          emptySubtitleEnglish:
                              'Every saved Jahez invoice from launch through today.',
                        ),
                        _cashierChannelList(
                          s,
                          dateFormat,
                          websiteOrders,
                          'لا توجد طلبات موقع',
                          'No website orders',
                        ),
                        if (widget.tableManagementEnabled)
                          _cashierChannelList(
                            s,
                            dateFormat,
                            hallTables,
                            'لا توجد طلبات صالة',
                            'No hall orders',
                          ),
                        _PosOnlineOrdersList(
                          orders: visiblePrevious,
                          dateFormat: dateFormat,
                          platforms: _platforms,
                          processingId: _processingId,
                          emptyTitle: s.tr(
                            'لا توجد طلبات محلية سابقة',
                            'No previous local orders',
                          ),
                          emptySubtitle: s.tr(
                            'طلبات الكاشير المحلية المنتهية تُحفظ هنا.',
                            'Finished local cashier orders are saved here.',
                          ),
                          onOpen: _openDetails,
                          readOnly: true,
                        ),
                        const PosDriverHandoffPage(showPageHeader: false),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _OnlineOrdersHeader extends StatelessWidget {
  const _OnlineOrdersHeader({
    required this.pendingCount,
    required this.currentCount,
    required this.previousCount,
    required this.shiftOpen,
    required this.onlineCashBound,
    required this.expectedCash,
    required this.cashierName,
  });

  final int pendingCount;
  final int currentCount;
  final int previousCount;
  final bool shiftOpen;
  final double onlineCashBound;
  final double expectedCash;
  final String cashierName;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: burgundy.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.qr_code_scanner, color: burgundy),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.tr('طلبات المنيو الإلكتروني', 'Online Menu Orders'),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: burgundy,
                      ),
                    ),
                    Text(
                      cashierName.isEmpty
                          ? s.tr(
                              'طلبات الموقع للعملاء — القبول يضيف الطلب لوردية الكاشير',
                              'Customer online orders — accepted orders enter the cashier shift',
                            )
                          : s.tr(
                              'حساب الكاشير: $cashierName — كل طلب تقبله يدخل ورديتك',
                              'Cashier: $cashierName — accepted orders enter your shift',
                            ),
                      style: const TextStyle(
                        color: Color(0xFF666666),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (pendingCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.orange.shade300),
                  ),
                  child: Text(
                    '$pendingCount ${s.tr('جديد', 'new')}',
                    style: TextStyle(
                      color: Colors.orange.shade900,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const PlatformTodaySyncButton(),
          if (shiftOpen) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetricChip(
                  icon: Icons.payments_outlined,
                  label: s.tr('كاش أونلاين محصّل', 'Online cash collected'),
                  value: '${onlineCashBound.toStringAsFixed(3)} د.ك',
                  color: Colors.green.shade700,
                ),
                _MetricChip(
                  icon: Icons.receipt_long_outlined,
                  label: s.tr('حالية في حسابك', 'Current in your account'),
                  value: '$currentCount',
                  color: burgundy,
                ),
                _MetricChip(
                  icon: Icons.inventory_2_outlined,
                  label: s.tr('سابقة في حسابك', 'Previous in your account'),
                  value: '$previousCount',
                  color: Colors.blueGrey,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static const burgundy = Color(0xFF6B1124);
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _PosOnlineOrdersList extends StatelessWidget {
  const _PosOnlineOrdersList({
    required this.orders,
    required this.dateFormat,
    required this.platforms,
    required this.processingId,
    required this.emptyTitle,
    required this.emptySubtitle,
    this.onAccept,
    this.onReject,
    this.onOpen,
    this.onNextStatus,
    this.onHandoffConfirm,
    this.readOnly = false,
    this.showDriverTracking = false,
  });

  final List<Order> orders;
  final DateFormat dateFormat;
  final List<SalesPlatformConfig> platforms;
  final String processingId;
  final String emptyTitle;
  final String emptySubtitle;
  final Future<void> Function(Order order)? onAccept;
  final Future<void> Function(Order order)? onReject;
  final Future<void> Function(Order order)? onOpen;
  final Future<void> Function(Order order, OrderStatus status)? onNextStatus;
  final Future<void> Function(Order order)? onHandoffConfirm;
  final bool readOnly;
  final bool showDriverTracking;

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return _EmptyOnlineOrders(title: emptyTitle, subtitle: emptySubtitle);
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: orders.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final order = orders[index];
        return _PosOnlineOrderCard(
          order: order,
          dateFormat: dateFormat,
          platforms: platforms,
          isProcessing: processingId == order.id,
          onAccept: onAccept == null ? null : () => onAccept!(order),
          onReject: onReject == null ? null : () => onReject!(order),
          onOpen: onOpen == null ? null : () => onOpen!(order),
          onHandoffConfirm: onHandoffConfirm == null
              ? null
              : () => onHandoffConfirm!(order),
          onNext:
              order.isHeldByDriver ||
                  order.status.nextStatus == null ||
                  onNextStatus == null ||
                  readOnly
              ? null
              : () => onNextStatus!(order, order.status.nextStatus!),
          nextLabel: order.status.nextActionLabel,
          lockedByDriver: order.isHeldByDriver,
          showDriverTracking: showDriverTracking,
        );
      },
    );
  }
}

class _PosOnlineOrderCard extends StatelessWidget {
  const _PosOnlineOrderCard({
    required this.order,
    required this.dateFormat,
    required this.platforms,
    required this.isProcessing,
    this.onAccept,
    this.onReject,
    this.onOpen,
    this.onHandoffConfirm,
    this.onNext,
    this.nextLabel,
    this.showDriverTracking = false,
    this.lockedByDriver = false,
  });

  final Order order;
  final DateFormat dateFormat;
  final List<SalesPlatformConfig> platforms;
  final bool isProcessing;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final VoidCallback? onOpen;
  final VoidCallback? onHandoffConfirm;
  final VoidCallback? onNext;
  final String? nextLabel;
  final bool showDriverTracking;
  final bool lockedByDriver;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final platform = PlatformCatalog.resolve(order.orderSource, platforms);
    final isCash = isCashPaymentMethod(order.paymentMethod);
    final itemSummary = order.items
        .map((item) => '${item.quantity}x ${item.name}')
        .join(' • ');

    return Card(
      elevation: order.status == OrderStatus.pending ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: order.status == OrderStatus.pending
              ? Colors.orange.shade300
              : const Color(0xFFE2E8F0),
          width: order.status == OrderStatus.pending ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order.customerName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '#${order.invoiceNumber ?? order.id.substring(0, 8)}',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  OrderStatusChip(
                    status: order.status,
                    label: order.cashierStatusLabel,
                  ),
                  if (order.status == OrderStatus.pending) ...[
                    const SizedBox(width: 8),
                    IncomingOrderCountdownBadge(orderId: order.id),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SalesPlatformBadge(platform: platform),
                  StoreNameBadge(storeName: order.storeName),
                  _IngestionSourceBadge(order: order),
                ],
              ),
              if ((order.externalOrderId ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  '${s.tr('رقم طلب المنصة', 'Platform order ID')}: #${order.externalOrderId}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
              if (order.receivedByCashierLabel.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '${s.tr('المستلم', 'Received by')}: ${order.receivedByCashierLabel}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6B1124),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              if (showDriverTracking &&
                  order.orderType == OrderType.delivery) ...[
                CashierHandshakePanel(
                  order: order,
                  processing: isProcessing,
                  onConfirm: onHandoffConfirm,
                ),
                const SizedBox(height: 8),
              ],
              Text('📞 ${order.phone}', style: const TextStyle(fontSize: 13)),
              Text(
                '📍 ${order.address.trim().isEmpty ? 'العنوان: —' : order.address}',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 8),
              Text(itemSummary, style: TextStyle(color: Colors.grey.shade800)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    '${order.totalPrice.toStringAsFixed(3)} د.ك',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF6B1124),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isCash
                          ? Colors.green.shade50
                          : Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      order.paymentMethod ?? '—',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isCash
                            ? Colors.green.shade800
                            : Colors.blue.shade800,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    dateFormat.format(order.createdAt.toLocal()),
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ],
              ),
              if (onAccept != null && isCash) ...[
                const SizedBox(height: 6),
                Text(
                  s.tr(
                    'سيُضاف هذا الطلب لورديتك عند القبول',
                    'This order will be added to your shift when accepted',
                  ),
                  style: TextStyle(fontSize: 12, color: Colors.green.shade700),
                ),
              ],
              if (onAccept != null && onReject != null) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: isProcessing ? null : onReject,
                        icon: const Icon(Icons.close, color: Colors.red),
                        label: Text(
                          s.tr('رفض', 'Reject'),
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: isProcessing ? null : onAccept,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF6B1124),
                        ),
                        icon: isProcessing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check_circle_outline),
                        label: Text(s.tr('قبول الأوردر', 'Accept order')),
                      ),
                    ),
                  ],
                ),
              ] else if (lockedByDriver) ...[
                const SizedBox(height: 12),
                const DriverCustodyLockBadge(),
              ] else if (onNext != null && nextLabel != null) ...[
                const SizedBox(height: 10),
                Text(
                  order.status == OrderStatus.confirmed
                      ? s.tr(
                          'الخطوة التالية: تحويل الطلب إلى «في الطريق»',
                          'Next: mark the order as on the way',
                        )
                      : s.tr(
                          'الخطوة التالية: تأكيد «تم التوصيل» لنقله للسابقة',
                          'Next: confirm delivery to archive the order',
                        ),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: isProcessing ? null : onNext,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                    backgroundColor: order.status == OrderStatus.confirmed
                        ? Colors.orange.shade700
                        : Colors.green.shade700,
                  ),
                  icon: Icon(
                    order.status == OrderStatus.confirmed
                        ? Icons.delivery_dining
                        : Icons.check_circle,
                  ),
                  label: Text(
                    s.isArabic
                        ? nextLabel!
                        : order.status == OrderStatus.confirmed
                        ? 'On the way'
                        : 'Delivered',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _IngestionSourceBadge extends StatelessWidget {
  const _IngestionSourceBadge({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final source = order.orderSource?.trim().toLowerCase() ?? '';
    final isPlatformOrder =
        source == 'talabat' ||
        source == 'jahez' ||
        source == 'keeta' ||
        source == 'keta';
    final mode = order.ingestionSource.trim().toUpperCase();
    if (!isPlatformOrder && mode.isEmpty) return const SizedBox.shrink();
    final isApi = mode == 'API';
    final color = isApi ? Colors.teal.shade700 : Colors.orange.shade800;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        isApi ? '⚡ API' : '👁️ DOM',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _EmptyOnlineOrders extends StatelessWidget {
  const _EmptyOnlineOrders({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.qr_code_2, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF6B1124),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionBanner extends StatelessWidget {
  const _PermissionBanner();

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Text(
        s.tr(
          'تحتاج صلاحية «استلام طلبات الموقع الإلكتروني للعملاء» لقبول الطلبات.',
          'You need the online-order permission to accept orders.',
        ),
        style: const TextStyle(fontSize: 13),
      ),
    );
  }
}

class _ShiftRequiredBanner extends StatelessWidget {
  const _ShiftRequiredBanner();

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Text(
        s.tr(
          'يجب فتح وردية POS قبل قبول الطلبات — لربط المبالغ النقدية بالعهدة.',
          'Open a POS shift before accepting orders so cash is assigned correctly.',
        ),
        style: const TextStyle(fontSize: 13, color: Color(0xFFB71C1C)),
      ),
    );
  }
}
