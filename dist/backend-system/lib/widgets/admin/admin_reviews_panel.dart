import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' as intl;

import '../../l10n/app_strings.dart';
import '../../models/restaurant_review.dart';
import '../../services/api_service.dart';
import '../../services/super_admin_scope_service.dart';
import '../../theme/app_theme.dart';
import 'admin_responsive_layout.dart';

class AdminReviewsPanel extends StatefulWidget {
  const AdminReviewsPanel({super.key});

  @override
  State<AdminReviewsPanel> createState() => _AdminReviewsPanelState();
}

class _AdminReviewsPanelState extends State<AdminReviewsPanel> {
  var _loading = true;
  String? _error;
  AdminReviewsPayload? _payload;
  var _includeHidden = true;

  String get _restaurantId =>
      SuperAdminScopeService.instance.effectiveRestaurantId;

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
      final payload = await ApiService.instance.fetchAdminReviews(
        restaurantId: _restaurantId,
        includeHidden: _includeHidden,
      );
      if (!mounted) return;
      setState(() {
        _payload = payload;
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

  Future<void> _toggleVisibility(RestaurantReview review) async {
    final next = review.isHidden ? 'published' : 'hidden';
    try {
      await ApiService.instance.updateReviewStatus(
        reviewId: review.id,
        status: next,
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
    final strings = AppStrings.of(context);
    final payload = _payload;
    final summary = payload?.summary ?? const ReviewSummary();
    final reviews = payload?.reviews ?? const <RestaurantReview>[];
    final trend = payload?.trend ?? const <ReviewTrendPoint>[];

    return ColoredBox(
      color: const Color(0xFFF4F1EE),
      child: RefreshIndicator(
        color: AppTheme.brandOrange,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            AdminSectionHeader(
              icon: Icons.star_rate_rounded,
              title: strings.navReviews,
              subtitle: strings.isArabic
                  ? 'تابع تقييمات العملاء وجودة الخدمة بعد التوصيل'
                  : 'Track customer ratings and service quality after delivery',
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(
                  child: CircularProgressIndicator(color: AppTheme.brandOrange),
                ),
              )
            else if (_error != null)
              _ErrorCard(message: _error!, onRetry: _load)
            else ...[
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _MetricCard(
                    label: strings.isArabic ? 'متوسط التقييم' : 'Average rating',
                    value: summary.hasReviews
                        ? summary.average.toStringAsFixed(1)
                        : '—',
                    icon: Icons.star_rounded,
                    color: AppTheme.brandOrange,
                  ),
                  _MetricCard(
                    label: strings.isArabic ? 'عدد التقييمات' : 'Total reviews',
                    value: '${summary.count}',
                    icon: Icons.reviews_outlined,
                    color: AppTheme.brandMaroon,
                  ),
                  _MetricCard(
                    label: strings.isArabic ? 'آخر 30 يوماً' : 'Last 30 days',
                    value:
                        '${trend.fold<int>(0, (sum, point) => sum + point.count)}',
                    icon: Icons.timeline,
                    color: const Color(0xFF2E7D32),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _DistributionCard(
                distribution: summary.distribution,
                isArabic: strings.isArabic,
              ),
              const SizedBox(height: 16),
              _TrendCard(trend: trend, isArabic: strings.isArabic),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    strings.isArabic ? 'التقييمات الواردة' : 'Incoming reviews',
                    style: GoogleFonts.cairo(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  FilterChip(
                    label: Text(
                      strings.isArabic ? 'إظهار المخفي' : 'Show hidden',
                    ),
                    selected: _includeHidden,
                    onSelected: (value) {
                      setState(() => _includeHidden = value);
                      _load();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (reviews.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    strings.isArabic
                        ? 'لا توجد تقييمات بعد. ستظهر هنا بعد توصيل الطلبات وتقييم العملاء.'
                        : 'No reviews yet. They appear here after orders are delivered and customers rate them.',
                    style: GoogleFonts.cairo(color: Colors.grey.shade700),
                  ),
                )
              else
                ...reviews.map(
                  (review) => _ReviewTile(
                    review: review,
                    isArabic: strings.isArabic,
                    onToggle: () => _toggleVisibility(review),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 210,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: GoogleFonts.cairo(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  label,
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DistributionCard extends StatelessWidget {
  const _DistributionCard({
    required this.distribution,
    required this.isArabic,
  });

  final Map<int, int> distribution;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final total = distribution.values.fold<int>(0, (a, b) => a + b);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isArabic ? 'توزيع النجوم' : 'Star distribution',
            style: GoogleFonts.cairo(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 12),
          for (var star = 5; star >= 1; star--)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      '$star',
                      style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const Icon(Icons.star, size: 16, color: AppTheme.brandOrange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: total == 0
                            ? 0
                            : (distribution[star] ?? 0) / total,
                        minHeight: 8,
                        backgroundColor: Colors.grey.shade200,
                        color: AppTheme.brandOrange,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${distribution[star] ?? 0}',
                      textAlign: TextAlign.end,
                      style: GoogleFonts.cairo(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.trend, required this.isArabic});

  final List<ReviewTrendPoint> trend;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final recent = trend.where((p) => p.count > 0).toList();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isArabic ? 'متوسط التقييم عبر الزمن' : 'Average rating over time',
            style: GoogleFonts.cairo(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 10),
          if (recent.isEmpty)
            Text(
              isArabic
                  ? 'لا توجد بيانات كافية بعد لعرض الاتجاه.'
                  : 'Not enough data yet to show a trend.',
              style: GoogleFonts.cairo(color: Colors.grey.shade700),
            )
          else
            SizedBox(
              height: 120,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: recent.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final point = recent[index];
                  return Container(
                    width: 84,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.brandOrange.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          point.average.toStringAsFixed(1),
                          style: GoogleFonts.cairo(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                            color: AppTheme.brandMaroon,
                          ),
                        ),
                        Text(
                          '${point.count}',
                          style: GoogleFonts.cairo(fontSize: 11),
                        ),
                        Text(
                          point.date.substring(5),
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({
    required this.review,
    required this.isArabic,
    required this.onToggle,
  });

  final RestaurantReview review;
  final bool isArabic;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final date = review.createdAt == null
        ? ''
        : intl.DateFormat('yyyy-MM-dd HH:mm').format(review.createdAt!.toLocal());

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: review.isHidden
              ? Colors.grey.shade300
              : AppTheme.brandOrange.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ...List.generate(
                5,
                (index) => Icon(
                  index < review.rating
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  size: 18,
                  color: AppTheme.brandOrange,
                ),
              ),
              const SizedBox(width: 8),
              if (review.isHidden)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isArabic ? 'مخفي' : 'Hidden',
                    style: GoogleFonts.cairo(fontSize: 11),
                  ),
                ),
              const Spacer(),
              TextButton(
                onPressed: onToggle,
                child: Text(
                  review.isHidden
                      ? (isArabic ? 'إظهار' : 'Publish')
                      : (isArabic ? 'إخفاء' : 'Hide'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            [
              if (review.customerName.trim().isNotEmpty) review.customerName,
              if (review.phone.trim().isNotEmpty) review.phone,
              if (review.invoiceNumber.trim().isNotEmpty)
                '#${review.invoiceNumber}',
              if (date.isNotEmpty) date,
            ].join(' · '),
            style: GoogleFonts.cairo(fontSize: 12, color: Colors.grey.shade700),
          ),
          if (review.comment.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              review.comment,
              style: GoogleFonts.cairo(fontSize: 14, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(message, style: GoogleFonts.cairo()),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
