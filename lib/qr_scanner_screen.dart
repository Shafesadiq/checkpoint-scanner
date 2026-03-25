import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'models.dart';

class QrScannerScreen extends StatefulWidget {
  final Function(CheckpointScan) onScanned;

  const QrScannerScreen({super.key, required this.onScanned});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _scanned = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan QR Code')),
      body: MobileScanner(
        controller: _controller,
        onDetect: (BarcodeCapture capture) {
          if (_scanned) return;
          final raw = capture.barcodes.first.rawValue;
          if (raw == null) return;

          _scanned = true;

          // Extract "211699" from "DD340206C445\nID:211699"
          final id =
              RegExp(r'ID[:\s]*(\w+)').firstMatch(raw)?.group(1) ?? raw;

          widget.onScanned(CheckpointScan(
            checkpointId: id,
            checkpointName: CheckpointRegistry.nameFor(id),
            method: ScanMethod.qr,
            timestamp: DateTime.now(),
          ));

          Navigator.of(context).pop();
        },
      ),
    );
  }
}
