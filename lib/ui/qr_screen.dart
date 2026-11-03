import 'package:flutter/material.dart' hide Text;
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme.dart';
import '../i18n.dart';

/// Сканер QR-кода с ключом или ссылкой на подписку. Возвращает текст из кода.
class QrScreen extends StatefulWidget {
  const QrScreen({super.key});

  @override
  State<QrScreen> createState() => _QrScreenState();
}

class _QrScreenState extends State<QrScreen> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Наведите на QR-код'),
      ),
      body: Stack(children: [
        MobileScanner(
          onDetect: (capture) {
            if (_done) return;
            for (final b in capture.barcodes) {
              final v = b.rawValue;
              if (v != null && v.trim().isNotEmpty) {
                _done = true;
                Navigator.of(context).pop(v.trim());
                return;
              }
            }
          },
        ),
        Center(
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: K.accent, width: 3),
              borderRadius: BorderRadius.circular(24),
            ),
          ),
        ),
      ]),
    );
  }
}
