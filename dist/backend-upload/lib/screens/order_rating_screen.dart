import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/order_rating_page.dart';
import '../providers/locale_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/language_toggle_button.dart';

class OrderRatingScreen extends StatefulWidget {
  const OrderRatingScreen({
    super.key,
    required this.orderId,
    required this.token,
  });

  final String orderId;
  final String token;

  @override
  State<OrderRatingScreen> createState() => _OrderRatingScreenState();
}

class _OrderRatingScreenState extends State<OrderRatingScreen> {
  OrderRatingPageData? _page;
  var _loading = true;
  String? _error;
  var _rating = 0;
  final _note = TextEditingController();
  var _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ApiService.instance.fetchOrderRatingPage(
        orderId: widget.orderId,
        token: widget.token,
      );
      if (!mounted) return;
      setState(() {
        _page = page;
        _rating = page.rating ?? 0;
        _note.text = page.reviewNote;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _submit() async {
    if (_rating < 1 || _rating > 5) {
      final strings = AppStrings.read(context);
      setState(
        () => _error = strings.tr(
          'يرجى اختيار تقييم من 1 إلى 5 نجوم',
          'Please select a rating from 1 to 5 stars',
        ),
      );
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final page = await ApiService.instance.submitOrderRating(
        orderId: widget.orderId,
        token: widget.token,
        rating: _rating,
        reviewNote: _note.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _page = page;
        _submitting = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Directionality(
      textDirection: context.watch<LocaleProvider>().textDirection,
      child: Scaffold(
        backgroundColor: AppTheme.brandBackground,
        appBar: AppBar(
          backgroundColor: AppTheme.brandMaroon,
          foregroundColor: Colors.white,
          title: Text(strings.tr('تقييم الطلب', 'Rate your order')),
          actions: const [
            LanguageToggleButton(compact: true, foregroundColor: Colors.white),
          ],
        ),
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppTheme.brandMaroon),
              )
            : _page == null
            ? _ErrorState(
                message:
                    _error ??
                    strings.tr(
                      'رابط التقييم غير صالح',
                      'This rating link is invalid',
                    ),
                onRetry: _load,
              )
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _OrderHeader(page: _page!),
                  const SizedBox(height: 16),
                  _ItemsCard(page: _page!),
                  const SizedBox(height: 16),
                  if (_page!.isRated)
                    _ThankYouCard(page: _page!)
                  else
                    _RatingForm(
                      rating: _rating,
                      noteController: _note,
                      submitting: _submitting,
                      error: _error,
                      onRating: (value) => setState(() => _rating = value),
                      onSubmit: _submit,
                    ),
                ],
              ),
      ),
    );
  }
}

class _OrderHeader extends StatelessWidget {
  const _OrderHeader({required this.page});

  final OrderRatingPageData page;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final date = page.createdAt == null
        ? '—'
        : DateFormat('yyyy/MM/dd  HH:mm').format(page.createdAt!.toLocal());
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              page.restaurantName.isEmpty
                  ? strings.tr('تفاصيل الطلب', 'Order details')
                  : page.restaurantName,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: AppTheme.brandMaroon,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '#${page.displayNumber}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text('${strings.tr('التاريخ', 'Date')}: $date'),
            Text(
              '${strings.tr('الدفع', 'Payment')}: '
              '${_localizedPayment(page.paymentMethod, strings)}',
            ),
            Text(
              '${strings.tr('الإجمالي', 'Total')}: '
              '${page.totalPrice.toStringAsFixed(3)} ${strings.currency}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemsCard extends StatelessWidget {
  const _ItemsCard({required this.page});

  final OrderRatingPageData page;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.tr('الأصناف', 'Items'),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 8),
            for (final line in page.items) ...[
              Text(
                '${line.quantity}x ${line.name} '
                '(${line.lineTotal.toStringAsFixed(3)} ${strings.currency})',
                style: const TextStyle(height: 1.5),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RatingForm extends StatelessWidget {
  const _RatingForm({
    required this.rating,
    required this.noteController,
    required this.submitting,
    required this.onRating,
    required this.onSubmit,
    this.error,
  });

  final int rating;
  final TextEditingController noteController;
  final bool submitting;
  final String? error;
  final ValueChanged<int> onRating;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              strings.tr('كيف كانت تجربتك؟', 'How was your experience?'),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var star = 1; star <= 5; star++)
                  IconButton(
                    onPressed: submitting ? null : () => onRating(star),
                    icon: Icon(
                      star <= rating ? Icons.star : Icons.star_border,
                      color: AppTheme.brandOrange,
                      size: 36,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: noteController,
              enabled: !submitting,
              minLines: 3,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: strings.tr(
                  'شارِكنا ملاحظاتك أو انطباعك عن الوجبة والتوصيل',
                  'Share your feedback about the meal and delivery',
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            if (error != null && error!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 12),
            FilledButton(
              onPressed: submitting ? null : onSubmit,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.brandMaroon,
              ),
              child: submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(strings.tr('إرسال التقييم', 'Submit rating')),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThankYouCard extends StatelessWidget {
  const _ThankYouCard({required this.page});

  final OrderRatingPageData page;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Card(
      color: const Color(0xFFF7F1EE),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(Icons.favorite, color: AppTheme.brandMaroon, size: 40),
            const SizedBox(height: 8),
            Text(
              strings.tr(
                'شكراً لتقييمك! رأيك يساعدنا نطور الخدمة.',
                'Thank you for your rating! Your feedback helps us improve.',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                height: 1.4,
              ),
            ),
            if (page.rating != null) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var star = 1; star <= 5; star++)
                    Icon(
                      star <= page.rating! ? Icons.star : Icons.star_border,
                      color: AppTheme.brandOrange,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onRetry,
              child: Text(
                AppStrings.of(context).tr('إعادة المحاولة', 'Try again'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _localizedPayment(String value, AppStrings strings) {
  final normalized = value.trim().toLowerCase();
  if (normalized.isEmpty) {
    return strings.tr('غير محدد', 'Not specified');
  }
  if (normalized.contains('cash') ||
      normalized.contains('كاش') ||
      normalized.contains('نقد')) {
    return strings.cash;
  }
  if (normalized.contains('k-net') ||
      normalized.contains('knet') ||
      normalized.contains('كي نت')) {
    return strings.knet;
  }
  return value;
}
