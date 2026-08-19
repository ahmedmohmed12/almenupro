import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/customer_checkout_profile.dart';
import '../models/loyalty_cashback.dart';
import '../services/api_service.dart';

class CustomerSessionProvider extends ChangeNotifier {
  static const _phoneKey = 'customer_session_phone';

  String _phone = '';
  CustomerCheckoutProfile? _profile;
  bool _isNew = true;
  bool _isReturning = false;
  bool _identified = false;
  bool _loading = false;
  String? _error;
  CashbackType _cashbackType = CashbackType.percentage;
  double _cashbackValue = 0;
  bool _loyaltyEnabled = false;

  String get phone => _phone;
  CustomerCheckoutProfile? get profile => _profile;
  bool get isNew => _isNew;
  bool get identified => _identified;
  bool get loading => _loading;
  String? get error => _error;
  double get walletBalance => _profile?.walletBalance ?? 0;
  bool get isReturning =>
      _isReturning ||
      (!_isNew &&
          ((_profile?.hasUsableData == true) ||
              (_profile?.walletBalance ?? 0) > 0 ||
              (_profile?.customerName.trim().isNotEmpty == true)));
  CashbackType get cashbackType => _cashbackType;
  double get cashbackValue => _cashbackValue;
  bool get loyaltyEnabled => _loyaltyEnabled;

  String get welcomeName {
    final name = _profile?.customerName.trim() ?? '';
    return name.isEmpty ? 'عميلنا' : name;
  }

  String get cashbackOfferLabel {
    if (!_loyaltyEnabled || _cashbackValue <= 0) {
      return 'اطلب الآن واجمع كاش باك على طلباتك';
    }
    if (_cashbackType == CashbackType.fixedAmount) {
      return 'كاش باك ${_cashbackValue.toStringAsFixed(3)} د.ك على كل طلب مكتمل';
    }
    return 'كاش باك ${_cashbackValue % 1 == 0 ? _cashbackValue.toStringAsFixed(0) : _cashbackValue.toStringAsFixed(1)}% عند التوصيل';
  }

  Future<void> restore({String? restaurantId}) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_phoneKey) ?? '';
    if (saved.replaceAll(RegExp(r'\D'), '').length < 8) return;
    await identify(saved, restaurantId: restaurantId);
  }

  Future<bool> identify(String rawPhone, {String? restaurantId}) async {
    final digits = rawPhone.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 8) {
      _error = 'أدخل رقم هاتف صحيح';
      notifyListeners();
      return false;
    }

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final map = await ApiService.instance.identifyCustomer(
        phone: digits,
        restaurantId: restaurantId,
      );
      final profileRaw = map['profile'];
      final loyaltyRaw = map['loyalty'];
      final loyalty = loyaltyRaw is Map
          ? Map<String, dynamic>.from(loyaltyRaw)
          : <String, dynamic>{};
      _phone = digits;
      _profile = CustomerCheckoutProfile.fromMap(
        profileRaw is Map
            ? Map<String, dynamic>.from(profileRaw)
            : {'phone': digits},
      );
      _isNew = map['isNew'] == true;
      _isReturning = map['isReturning'] == true;
      _identified = true;
      _cashbackType = CashbackType.fromStorage(
        loyalty['cashbackType']?.toString(),
      );
      _cashbackValue = (loyalty['cashbackValue'] as num?)?.toDouble() ?? 0;
      _loyaltyEnabled = loyalty['loyaltyEnabled'] == true || _cashbackValue > 0;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_phoneKey, digits);
      _loading = false;
      notifyListeners();
      return true;
    } catch (error) {
      _loading = false;
      _error = error.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  void applyWalletDebit(double amount) {
    final current = _profile;
    if (current == null || amount <= 0) return;
    _profile = CustomerCheckoutProfile(
      phone: current.phone,
      customerName: current.customerName,
      governorate: current.governorate,
      areaName: current.areaName,
      deliveryZoneId: current.deliveryZoneId,
      addressDetails: current.addressDetails,
      paymentMethod: current.paymentMethod,
      customerId: current.customerId,
      personalPromoCode: current.personalPromoCode,
      personalPromoDiscount: current.personalPromoDiscount,
      walletBalance: (current.walletBalance - amount).clamp(0, current.walletBalance),
      walletPromoCode: current.walletPromoCode,
    );
    notifyListeners();
  }
}
