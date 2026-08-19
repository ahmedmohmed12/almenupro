import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/customer_session_provider.dart';
import '../../theme/app_theme.dart';

class CustomerPhoneGate extends StatefulWidget {
  const CustomerPhoneGate({super.key, this.restaurantId});

  final String? restaurantId;

  @override
  State<CustomerPhoneGate> createState() => _CustomerPhoneGateState();
}

class _CustomerPhoneGateState extends State<CustomerPhoneGate> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final session = context.read<CustomerSessionProvider>();
    await session.identify(
      _controller.text,
      restaurantId: widget.restaurantId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<CustomerSessionProvider>();
    final media = MediaQuery.of(context);
    final compact = media.size.width < 420 || media.size.height < 620;

    return SizedBox.expand(
      child: Material(
        color: Colors.black.withValues(alpha: 0.55),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxCardWidth = constraints.maxWidth >= 720 ? 460.0 : 420.0;
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  compact ? 12 : 24,
                  16,
                  16 + media.viewInsets.bottom,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: (constraints.maxHeight - 32).clamp(0, 4000),
                    maxWidth: constraints.maxWidth,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxCardWidth),
                      child: Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        clipBehavior: Clip.antiAlias,
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            compact ? 16 : 22,
                            compact ? 18 : 24,
                            compact ? 16 : 22,
                            compact ? 16 : 20,
                          ),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: compact ? 52 : 64,
                                  height: compact ? 52 : 64,
                                  decoration: BoxDecoration(
                                    color: AppTheme.brandMaroon
                                        .withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.phone_iphone,
                                    color: AppTheme.brandMaroon,
                                    size: compact ? 26 : 32,
                                  ),
                                ),
                                SizedBox(height: compact ? 10 : 14),
                                Text(
                                  'أهلاً بك',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: compact ? 20 : 22,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.brandMaroon,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'أدخل رقم هاتفك للمتابعة وعرض رصيد الكاش باك',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Color(0xFF5C4A42),
                                    height: 1.35,
                                  ),
                                ),
                                SizedBox(height: compact ? 14 : 18),
                                TextFormField(
                                  controller: _controller,
                                  keyboardType: TextInputType.phone,
                                  textDirection: TextDirection.ltr,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  decoration: InputDecoration(
                                    labelText: 'رقم الهاتف',
                                    hintText: '9xxxxxxx',
                                    isDense: compact,
                                    prefixIcon: const Icon(Icons.phone),
                                    border: const OutlineInputBorder(),
                                  ),
                                  validator: (value) {
                                    final digits = (value ?? '')
                                        .replaceAll(RegExp(r'\D'), '');
                                    if (digits.length < 8) {
                                      return 'أدخل رقم هاتف صحيح';
                                    }
                                    return null;
                                  },
                                  onFieldSubmitted: (_) => _submit(),
                                ),
                                if (session.error != null) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    session.error!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.red,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                                SizedBox(height: compact ? 12 : 16),
                                SizedBox(
                                  width: double.infinity,
                                  height: 48,
                                  child: FilledButton(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: AppTheme.brandMaroon,
                                    ),
                                    onPressed:
                                        session.loading ? null : _submit,
                                    child: session.loading
                                        ? const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Text(
                                            'دخول',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
