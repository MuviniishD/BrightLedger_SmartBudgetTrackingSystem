import 'package:flutter/material.dart';

/// Shared ChangeNotifier that lets any screen programmatically
/// switch to a different bottom-navigation tab.
///
/// Tab indices:
///   0 = Home, 1 = Add, 2 = Records, 3 = Stats, 4 = Account
class TabNotifier extends ChangeNotifier {
  int _index = 0;

  int get index => _index;

  void jumpTo(int index) {
    if (_index == index) return;
    _index = index;
    notifyListeners();
  }
}
