import 'package:flutter/material.dart';

class KakaoMapView extends StatelessWidget {
  final double centerLat;
  final double centerLng;
  final List<Map<String, dynamic>> pins;
  final Function(String id, String title, bool isStacked)? onPinClicked;

  const KakaoMapView({
    super.key,
    required this.centerLat,
    required this.centerLng,
    this.pins = const [],
    this.onPinClicked,
  });

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
