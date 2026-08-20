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

bool _offerAppliesToItem(Offer offer, MenuItem item) {
  if (!offer.isLive || offer.isCombo) return false;
  if (offer.isCartLevel) return true;
  return offer.itemIds.contains(item.id);
}

/// Applies live percentage/fixed offers onto catalog prices.
/// Store-wide (cart-level) offers mark down every item.
/// Combo offers do not rewrite individual card prices.
/// Items that already have [MenuItem.hasDiscount] are left unchanged.
List<MenuItem> applyOfferDiscountsToItems(
  List<MenuItem> items,
  List<Offer> offers,
) {
  final live = offers
      .where((offer) => offer.isLive && !offer.isCombo)
      .toList();
  if (live.isEmpty) return items;

  return items.map((item) {
    if (item.hasDiscount) return item;
    double? bestSale;
    for (final offer in live) {
      if (!_offerAppliesToItem(offer, item)) continue;
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

/// Products to show in the Offers tab: discounted items, or the full menu
/// when a live store-wide percentage/fixed offer is active.
List<MenuItem> itemsForOffersTab(
  List<MenuItem> pricedItems,
  List<Offer> offers,
) {
  final live = offers.where((offer) => offer.isLive && !offer.isCombo).toList();
  final storeWide = live.any((offer) => offer.isCartLevel);
  if (storeWide) return pricedItems;

  final targetedIds = <int>{
    for (final offer in live) ...offer.itemIds,
  };
  return pricedItems
      .where(
        (item) => item.hasDiscount || targetedIds.contains(item.id),
      )
      .toList();
}

String? matchingOfferIdForItem(MenuItem item, List<Offer> offers) {
  Offer? best;
  for (final offer in offers) {
    if (!_offerAppliesToItem(offer, item)) continue;
    if (best == null) {
      best = offer;
      continue;
    }
    if (!offer.isCartLevel && best.isCartLevel) best = offer;
  }
  return best?.id;
}
