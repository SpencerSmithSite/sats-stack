import 'package:flutter/material.dart';

/// The icons a category can have, by the name stored in `categories.icon`, in
/// the order the picker offers them.
///
/// One map. The categories sheet and the transaction rows each had their own
/// copy (audit U-22), so an icon added to the picker would have shown as the
/// fallback in the list.
const categoryIcons = <String, IconData>{
  'restaurant': Icons.restaurant,
  'coffee': Icons.coffee,
  'directions_car': Icons.directions_car,
  'local_gas_station': Icons.local_gas_station,
  'flight': Icons.flight,
  'home': Icons.home,
  'bed': Icons.bed,
  'shopping_bag': Icons.shopping_bag,
  'shopping_cart': Icons.shopping_cart,
  'subscriptions': Icons.subscriptions,
  'movie': Icons.movie,
  'sports_esports': Icons.sports_esports,
  'fitness_center': Icons.fitness_center,
  'local_hospital': Icons.local_hospital,
  'school': Icons.school,
  'work': Icons.work,
  'computer': Icons.computer,
  'phone_android': Icons.phone_android,
  'currency_bitcoin': Icons.currency_bitcoin,
  'payments': Icons.payments,
  'savings': Icons.savings,
  'attach_money': Icons.attach_money,
  'pets': Icons.pets,
  'child_care': Icons.child_care,
  'park': Icons.park,
  'celebration': Icons.celebration,
  'card_giftcard': Icons.card_giftcard,
  'more_horiz': Icons.more_horiz,
};

/// The icon named [name], or [fallback] for a name not in [categoryIcons].
IconData categoryIcon(String? name, {IconData fallback = Icons.receipt_long}) =>
    categoryIcons[name] ?? fallback;
