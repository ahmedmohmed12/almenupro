import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/app_strings.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';

/// Post-delivery review prompt. Must only be shown when eligibility is true.
class OrderReviewSheet extends StatefulWidget {
  const OrderReviewSheet({
    super.key,
    required this.orderId,
    required this.restaurantId,
    required this.strings,
    this.restaurantSlug,
    this.restaurantName = '',
    this.invoiceNumber = '',
    this.customerName = '',
    this.phone = '',
  });

  final String orderId;
  final String restaurantId;
  final String? restaurantSlug;
  final String restaurantName;
  final String invoiceNumber;
  final String customerName;
  final String phone;
  final AppStrings strings;

  static Future<bool?> show(
    BuildContext context, {
    required String orderId,
    required String restaurantId,
    required AppStrings strings,
    String? restaurantSlug,
    String restaurantName = '',
    String invoiceNumber = '',
    String customerName = '',
    String phone = '',
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => OrderReviewSheet(
        orderId: orderId,
        restaurantId: restaurantId,
        restaurantSlug: restaurantSlug,
        restaurantName: restaurantName,
        invoiceNumber: invoiceNumber,
        customerName: customerName,
        phone: phone,
        strings: strings,
      ),
    );
  }

  @override
  State<OrderReviewSheet> createState() => _OrderReviewSheetState();
}

class _OrderReviewSheetState extends State<OrderReviewSheet> {
  int _rating = 0;
  final _commentController = TextEditingController();
  var _submitting = false;
  String? _error;

  bool get _isArabic => widget.strings.isArabic;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating < 1) {
      setState(() {
        _error = _isArabic
            ? 'يرجى اختيار تقييم من 1 إلى 5 نجوم'
            : 'Please choose a rating from 1 to 5 stars';
      });
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await ApiService.instance.submitRestaurantReview(
        orderId: widget.orderId,
        rating: _rating,
        comment: _commentController.text.trim(),
        restaurantId: widget.restaurantId,
        slug: widget.restaurantSlug,
        customerName: widget.customerName,
        phone: widget.phone,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isArabic
                ? 'شكراً لتقييمك! رأيك يساعدنا على التحسين'
                : 'Thanks for your review! Your feedback helps us improve',
            style: GoogleFonts.cairo(),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final name = widget.restaurantName.trim().isNotEmpty
        ? widget.restaurantName.trim()
        : (_isArabic ? 'المطعم' : 'the restaurant');

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _isArabic ? 'كيف كانت تجربتك؟' : 'How was your experience?',
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.brandBlack,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _isArabic
                    ? 'طلبك من $name تم توصيله — قيّم الخدمة لمساعدتنا على التحسين'
                    : 'Your order from $name was delivered — rate the service to help us improve',
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  fontSize: 13,
                  color: const Color(0xFF666666),
                ),
              ),
              if (widget.invoiceNumber.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  _isArabic
                      ? 'طلب #${widget.invoiceNumber}'
                      : 'Order #${widget.invoiceNumber}',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.brandMaroon,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  final star = index + 1;
                  final selected = star <= _rating;
                  return IconButton(
                    onPressed: _submitting
                        ? null
                        : () => setState(() {
                              _rating = star;
                              _error = null;
                            }),
                    icon: Icon(
                      selected ? Icons.star_rounded : Icons.star_outline_rounded,
                      size: 36,
                      color: selected
                          ? AppTheme.brandOrange
                          : Colors.grey.shade400,
                    ),
                  );
                }),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _commentController,
                enabled: !_submitting,
                minLines: 3,
                maxLines: 5,
                maxLength: 1000,
                decoration: InputDecoration(
                  hintText: _isArabic
                      ? 'ملاحظة اختيارية (اختياري)'
                      : 'Optional feedback',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: GoogleFonts.cairo(
                    color: Colors.red.shade700,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.brandMaroon,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        _isArabic ? 'إرسال التقييم' : 'Submit review',
                        style: GoogleFonts.cairo(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
              ),
              TextButton(
                onPressed: _submitting
                    ? null
                    : () => Navigator.of(context).pop(false),
                child: Text(
                  _isArabic ? 'لاحقاً' : 'Maybe later',
                  style: GoogleFonts.cairo(color: Colors.grey.shade700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
