import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/order.dart';
import '../../providers/cart_provider.dart';
import '../../providers/order_type_provider.dart';
import '../../services/firebase_service.dart';

Future<void> showGuestCheckoutDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const GuestCheckoutDialog(),
  );
}

class GuestCheckoutDialog extends StatefulWidget {
  const GuestCheckoutDialog({super.key});

  @override
  State<GuestCheckoutDialog> createState() => _GuestCheckoutDialogState();
}

class _GuestCheckoutDialogState extends State<GuestCheckoutDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _firebaseService = FirebaseService();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final cart = context.read<CartProvider>();
    final orderType = context.read<OrderTypeProvider>().orderType;

    if (cart.isEmpty) {
      return;
    }

    setState(() => _isSubmitting = true);

    final order = Order(
      id: '',
      customerName: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      address: orderType == OrderType.pickup
          ? 'Pickup'
          : _addressController.text.trim(),
      items: cart.items.map(OrderLineItem.fromCartItem).toList(),
      totalPrice: cart.totalPrice,
      orderType: orderType,
      status: OrderStatus.pending,
      createdAt: DateTime.now(),
    );

    try {
      final orderId = await _firebaseService.addOrder(order);
      cart.clear();

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop();
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.check_circle_outline, size: 48),
          title: const Text('Order placed!'),
          content: Text(
            'Thank you, ${order.customerName}. Your order #${orderId.substring(0, 6)} has been received.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not place order: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final orderType = context.watch<OrderTypeProvider>().orderType;
    final isDelivery = orderType == OrderType.delivery;

    return AlertDialog(
      title: const Text('Guest checkout'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isDelivery
                    ? 'Enter your details for delivery.'
                    : 'Enter your details for pickup.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Customer name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Name is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone number',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                validator: (value) {
                  if (value == null || value.trim().length < 8) {
                    return 'Enter a valid phone number';
                  }
                  return null;
                },
              ),
              if (isDelivery) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _addressController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Delivery address',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Address is required for delivery';
                    }
                    return null;
                  },
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Place order'),
        ),
      ],
    );
  }
}
