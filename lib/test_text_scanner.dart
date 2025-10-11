import 'package:flutter/material.dart';
import 'screens/text_scanner_screen.dart';

void main() {
  runApp(const TextScannerTestApp());
}

class TextScannerTestApp extends StatelessWidget {
  const TextScannerTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Text Scanner Test',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const TextScannerTestScreen(),
    );
  }
}

class TextScannerTestScreen extends StatefulWidget {
  const TextScannerTestScreen({super.key});

  @override
  State<TextScannerTestScreen> createState() => _TextScannerTestScreenState();
}

class _TextScannerTestScreenState extends State<TextScannerTestScreen> {
  String _scannedText = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Test Text Scanner'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Text Scanner Test',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            const Text(
              'Nhấn nút bên dưới để test chức năng quét text (chỉ số)',
              style: TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () async {
                final result = await Navigator.push<String>(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const TextScannerScreen(),
                  ),
                );
                
                if (result != null) {
                  setState(() {
                    _scannedText = result;
                  });
                  
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Đã quét được: $result'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.text_fields),
              label: const Text('Mở Text Scanner'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
              ),
            ),
            const SizedBox(height: 20),
            if (_scannedText.isNotEmpty) ...[
              const Text(
                'Kết quả quét:',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  border: Border.all(color: Colors.green),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _scannedText,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            const Text(
              'Hướng dẫn sử dụng:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              '1. Nhấn "Mở Text Scanner"\n'
              '2. Đặt số cần quét vào khung đỏ\n'
              '3. Nhấn nút camera để chụp\n'
              '4. Số sẽ được nhận dạng và trả về',
              style: TextStyle(fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
