import 'package:flutter/material.dart';

class WebAdSlotView extends StatelessWidget {
  final String network; // 'adfit' or 'adsense'
  final String adUnitId;
  final String? adsenseClientId;
  final String? adsenseSlotId;
  final Widget fallbackChild;

  const WebAdSlotView({
    super.key,
    required this.network,
    required this.adUnitId,
    this.adsenseClientId,
    this.adsenseSlotId,
    required this.fallbackChild,
  });

  @override
  Widget build(BuildContext context) {
    return fallbackChild;
  }
}
