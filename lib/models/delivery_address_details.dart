class DeliveryAddressDetails {
  const DeliveryAddressDetails({
    this.block = '',
    this.street = '',
    this.avenue = '',
    this.houseNumber = '',
    this.floorApartment = '',
  });

  final String block;
  final String street;
  final String avenue;
  final String houseNumber;
  final String floorApartment;

  factory DeliveryAddressDetails.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const DeliveryAddressDetails();
    return DeliveryAddressDetails(
      block: map['block']?.toString() ?? '',
      street: map['street']?.toString() ?? '',
      avenue: map['avenue']?.toString() ?? '',
      houseNumber:
          map['houseNumber']?.toString() ?? map['house_number']?.toString() ?? '',
      floorApartment: map['floorApartment']?.toString() ??
          map['floor_apartment']?.toString() ??
          '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'block': block,
      'street': street,
      if (avenue.isNotEmpty) 'avenue': avenue,
      'houseNumber': houseNumber,
      if (floorApartment.isNotEmpty) 'floorApartment': floorApartment,
    };
  }

  bool get isEmpty =>
      block.isEmpty &&
      street.isEmpty &&
      avenue.isEmpty &&
      houseNumber.isEmpty &&
      floorApartment.isEmpty;

  String formatArabic({
    required String governorate,
    required String areaName,
  }) {
    final parts = <String>[
      if (governorate.isNotEmpty) governorate,
      if (areaName.isNotEmpty) areaName,
      if (block.isNotEmpty) 'قطعة $block',
      if (street.isNotEmpty) 'شارع $street',
      if (avenue.isNotEmpty) 'جادة $avenue',
      if (houseNumber.isNotEmpty) 'مبنى $houseNumber',
      if (floorApartment.isNotEmpty) 'طابق/شقة $floorApartment',
    ];
    return parts.join('، ');
  }
}
