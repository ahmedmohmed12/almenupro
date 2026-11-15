class SignupRequest {
  const SignupRequest({
    required this.id,
    required this.ownerName,
    required this.email,
    required this.phone,
    required this.restaurantName,
    required this.slug,
    this.instagram = '',
    this.status = 'new',
    this.createdAt,
    this.emailSent = false,
    this.emailError = '',
  });

  final String id;
  final String ownerName;
  final String email;
  final String phone;
  final String restaurantName;
  final String slug;
  final String instagram;
  final String status;
  final DateTime? createdAt;
  final bool emailSent;
  final String emailError;

  bool get isNew => status == 'new';

  String get statusLabelAr {
    switch (status) {
      case 'read':
        return 'مقروء';
      case 'accepted':
        return 'مقبول';
      case 'rejected':
        return 'مرفوض';
      default:
        return 'جديد';
    }
  }

  factory SignupRequest.fromJson(Map<String, dynamic> json) {
    return SignupRequest(
      id: json['id']?.toString() ?? '',
      ownerName: json['ownerName']?.toString() ?? json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      restaurantName:
          json['restaurantName']?.toString() ?? json['storeName']?.toString() ?? '',
      slug: json['slug']?.toString() ?? '',
      instagram: json['instagram']?.toString() ?? '',
      status: json['status']?.toString() ?? 'new',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      emailSent: json['emailSent'] == true,
      emailError: json['emailError']?.toString() ?? '',
    );
  }
}
