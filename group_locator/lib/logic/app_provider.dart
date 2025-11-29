import 'package:flutter/material.dart';

class AppState extends ChangeNotifier {
  bool initialized = false;

  void setInitialized() {
    initialized = true;
    notifyListeners();
  }
}
