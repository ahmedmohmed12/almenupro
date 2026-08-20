import '../models/menu_item.dart';
import '../models/offer.dart';

/// Returns a whole-number discount like `20` for a "-20%" badge, or null
/// when there is no real markdown (`original` missing, not greater than [finalPrice]).
int? calculateDiscountPercentage(num? original, num finalPrice) {
  if (original == null) return null;
  final list = original.toDouble();
  final sale = finalPrice.toDouble();
  if (list <= 0 || sale < 0 || list <= sale + 0.0005) return null;
  final percent = (((list - sale) / list) * 100).round();
  if (percent <= 0) return null;
  return percent;
}

/// Applies live item-scoped percentage/fixed offers onto catalog prices.
/// Items that already have [MenuItem.hasDiscount] are left unchanged.
/// Combo and cart-level offers (empty [Offer.itemIds]) do not rewrite cards.
List<MenuItem> applyOfferDiscountsToItems(
  List<MenuItem> items,
  List<Offer> offers,
) {
  final live = offers
      .where(
        (offer) => offer.isLive && !offer.isCombo && offer.itemIds.isNotEmpty,
      )
      .toList();
  if (live.isEmpty) return items;

  return items.map((item) {
    if (item.hasDiscount) return item;
    double? bestSale;
    for (final offer in live) {
      if (!offer.itemIds.contains(item.id)) continue;
      final sale = offer.discountedUnitPrice(item.price);
      if (sale < item.price - 0.0005 &&
          (bestSale == null || sale < bestSale)) {
        bestSale = sale;
      }
    }
    if (bestSale == null) return item;
    return item.copyWith(price: bestSale, originalPrice: item.price);
  }).toList();
}
