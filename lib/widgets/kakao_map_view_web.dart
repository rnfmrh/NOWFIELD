// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:ui_web' as ui_web;
import 'dart:html' as html;
import 'dart:js' as js;

class KakaoMapView extends StatefulWidget {
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
  State<KakaoMapView> createState() => _KakaoMapViewState();
}

class _KakaoMapViewState extends State<KakaoMapView> {
  static int _viewCounter = 0;
  late final String _viewId;
  late final String _elementId;
  bool _isMapReady = false;

  @override
  void initState() {
    super.initState();
    _viewCounter++;
    _viewId = 'kakao-map-view-$_viewCounter';
    _elementId = 'kakao_map_container_$_viewCounter';

    if (kIsWeb) {
      ui_web.platformViewRegistry.registerViewFactory(
        _viewId,
        (int id) {
          final div = html.DivElement()
            ..id = _elementId
            ..style.width = '100%'
            ..style.height = '100%'
            ..style.backgroundColor = '#0A1426';
          return div;
        },
      );

      js.context['onKakaoPinClicked'] = (String id, String title, bool isStacked) {
        if (widget.onPinClicked != null) {
          widget.onPinClicked!(id, title, isStacked);
        }
      };

      WidgetsBinding.instance.addPostFrameCallback((_) => _initMap());
    }
  }

  void _initMap() {
    if (!kIsWeb) return;

    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      if (js.context.hasProperty('initKakaoMap')) {
        final success = js.context.callMethod('initKakaoMap', [
          _elementId,
          widget.centerLat,
          widget.centerLng,
          4,
        ]);
        if (success == true) {
          setState(() {
            _isMapReady = true;
          });
          _renderPins();
        }
      }
    });
  }

  void _renderPins() {
    if (!_isMapReady || widget.pins.isEmpty) return;
    if (js.context.hasProperty('renderKakaoPins')) {
      final jsPins = widget.pins
          .map((p) => js.JsObject.jsify({
                'id': p['id'],
                'title': p['title'],
                'lat': p['lat'],
                'lng': p['lng'],
                'isStacked': p['isStacked'],
                'locationMode': p['locationMode'] ?? 'exact',
              }))
          .toList();
      js.context.callMethod('renderKakaoPins', [js.JsArray.from(jsPins)]);
    }
  }

  @override
  void didUpdateWidget(covariant KakaoMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isMapReady && widget.pins != oldWidget.pins) {
      _renderPins();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      return const SizedBox.shrink();
    }
    return HtmlElementView(viewType: _viewId);
  }
}
