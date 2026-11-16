import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app/theme.dart';
import 'startv_models.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({
    super.key,
    required this.title,
    required this.hint,
  });

  final String title;
  final String hint;

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue?.trim() ?? '';
      if (raw.isEmpty) continue;
      if (StarTvQrPayload.tryParse(raw) != null) {
        _handled = true;
        Navigator.of(context).pop(raw);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on_outlined),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: StarFilmColors.lime, width: 3),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 40,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: StarFilmColors.background.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                widget.hint,
                textAlign: TextAlign.center,
                style: const TextStyle(color: StarFilmColors.textPrimary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
