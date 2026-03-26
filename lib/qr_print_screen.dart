import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'tag_service.dart';

class QrPrintScreen extends StatefulWidget {
  const QrPrintScreen({super.key});

  @override
  State<QrPrintScreen> createState() => _QrPrintScreenState();
}

class _QrPrintScreenState extends State<QrPrintScreen> {
  final _svc = TagService();

  @override
  void initState() {
    super.initState();
    _svc.addListener(_update);
  }

  @override
  void dispose() {
    _svc.removeListener(_update);
    super.dispose();
  }

  void _update() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Only QR-type checkpoints — these are the ones you print and stick on walls
    final qrCps =
        _svc.checkpoints.where((c) => c.type == CheckpointType.qr).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('Print QR Codes (${qrCps.length})'),
        actions: [
          if (qrCps.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf),
              tooltip: 'Export PDF',
              onPressed: () => _exportPdf(qrCps),
            ),
        ],
      ),
      body: qrCps.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.qr_code, size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  const Text('No QR checkpoints yet',
                      style: TextStyle(fontSize: 18, color: Colors.grey)),
                  const SizedBox(height: 4),
                  const Text(
                      'Go to Checkpoints → + → QR Code to create one',
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  color: Colors.blue.shade50,
                  padding: const EdgeInsets.all(12),
                  child: const Text(
                    'Print these QR codes and place them at the checkpoint locations.\n'
                    'Guards scan them during patrol to check in.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.75,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: qrCps.length,
                    itemBuilder: (_, i) {
                      final cp = qrCps[i];
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            children: [
                              Expanded(
                                child: QrImageView(
                                  data: cp.qrData,
                                  size: double.infinity,
                                  backgroundColor: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text('#${cp.id}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16)),
                              Text(cp.name,
                                  style: const TextStyle(fontSize: 12),
                                  maxLines: 2,
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                // Export button at bottom
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton.icon(
                      onPressed: () => _exportPdf(qrCps),
                      icon: const Icon(Icons.picture_as_pdf),
                      label: Text(
                          'Export PDF (${qrCps.length} QR codes)',
                          style: const TextStyle(fontSize: 16)),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _exportPdf(List<Checkpoint> cps) async {
    final pdf = pw.Document();

    // 4 QR codes per page (2x2)
    const perPage = 4;
    for (var page = 0; page < cps.length; page += perPage) {
      final pageItems = cps.skip(page).take(perPage).toList();

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(20),
          build: (ctx) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Checkpoint QR Codes',
                    style: pw.TextStyle(
                        fontSize: 16, fontWeight: pw.FontWeight.bold)),
                pw.Text(
                    'Page ${(page ~/ perPage) + 1} - Print and place at locations',
                    style: const pw.TextStyle(
                        fontSize: 10, color: PdfColors.grey)),
                pw.SizedBox(height: 16),
                pw.Wrap(
                  spacing: 20,
                  runSpacing: 20,
                  children: pageItems.map((cp) {
                    return pw.Container(
                      width: 240,
                      padding: const pw.EdgeInsets.all(16),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: PdfColors.grey400),
                        borderRadius: pw.BorderRadius.circular(8),
                      ),
                      child: pw.Column(
                        children: [
                          pw.BarcodeWidget(
                            data: cp.qrData,
                            barcode: pw.Barcode.qrCode(),
                            width: 150,
                            height: 150,
                          ),
                          pw.SizedBox(height: 10),
                          pw.Text('#${cp.id}',
                              style: pw.TextStyle(
                                  fontSize: 20,
                                  fontWeight: pw.FontWeight.bold)),
                          pw.Text(cp.name,
                              style: const pw.TextStyle(fontSize: 13)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            );
          },
        ),
      );
    }

    await Printing.layoutPdf(
      onLayout: (_) async => pdf.save(),
      name: 'checkpoint_qr_codes',
    );
  }
}
