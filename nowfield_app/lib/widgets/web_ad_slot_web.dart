// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class WebAdSlotView extends StatefulWidget {
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
  State<WebAdSlotView> createState() => _WebAdSlotViewState();
}

class _WebAdSlotViewState extends State<WebAdSlotView> {
  static int _slotCounter = 0;
  late final String _viewType;

  bool get _hasRealExternalAdCode {
    if (widget.network.toLowerCase() == 'adsense') {
      final client = (widget.adsenseClientId ?? '').trim();
      final slot = (widget.adsenseSlotId ?? '').trim();
      return client.startsWith('ca-pub-') &&
          !client.contains('00000000') &&
          slot.isNotEmpty;
    }
    // Kakao AdFit
    final unit = widget.adUnitId.trim();
    return unit.startsWith('DAN-') && unit != 'DAN-NOWFIELD01' && unit != 'DAN-NOWFIELD02';
  }

  @override
  void initState() {
    super.initState();
    _slotCounter++;
    _viewType = 'nowfield-web-ad-slot-$_slotCounter';

    if (kIsWeb && _hasRealExternalAdCode) {
      ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
        final wrapper = html.DivElement()
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.display = 'flex'
          ..style.alignItems = 'center'
          ..style.justifyContent = 'center'
          ..style.overflow = 'hidden'
          ..style.borderRadius = '14px';

        if (widget.network.toLowerCase() == 'adsense') {
          final ins = html.Element.tag('ins')
            ..classes.add('adsbygoogle')
            ..style.display = 'block'
            ..style.width = '300px'
            ..style.height = '250px'
            ..setAttribute('data-ad-client', widget.adsenseClientId ?? '')
            ..setAttribute('data-ad-slot', widget.adsenseSlotId ?? '')
            ..setAttribute('data-ad-format', 'auto')
            ..setAttribute('data-full-width-responsive', 'true');
          wrapper.append(ins);

          final script = html.ScriptElement()
            ..async = true
            ..src =
                'https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=${widget.adsenseClientId}';
          wrapper.append(script);

          final pushScript = html.ScriptElement()
            ..text = '(adsbygoogle = window.adsbygoogle || []).push({});';
          wrapper.append(pushScript);
        } else {
          // Kakao AdFit Web tag (<ins class="kakao_ad_area">)
          final ins = html.Element.tag('ins')
            ..classes.add('kakao_ad_area')
            ..style.display = 'none'
            ..setAttribute('data-ad-unit', widget.adUnitId.trim())
            ..setAttribute('data-ad-width', '300')
            ..setAttribute('data-ad-height', '250');
          wrapper.append(ins);

          final script = html.ScriptElement()
            ..type = 'text/javascript'
            ..src = 'https://t1.daumcdn.net/kas/static/ba.min.js'
            ..async = true;
          wrapper.append(script);
        }

        return wrapper;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb || !_hasRealExternalAdCode) {
      return widget.fallbackChild;
    }
    return Stack(
      children: [
        widget.fallbackChild,
        Positioned.fill(
          child: HtmlElementView(viewType: _viewType),
        ),
      ],
    );
  }
}
