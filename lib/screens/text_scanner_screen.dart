import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'dart:io';

class TextScannerScreen extends StatefulWidget {
  const TextScannerScreen({super.key});

  @override
  State<TextScannerScreen> createState() => _TextScannerScreenState();
}

class _TextScannerScreenState extends State<TextScannerScreen> {
  CameraController? _cameraController;
  TextRecognizer? _textRecognizer;
  bool _isInitialized = false;
  bool _isProcessing = false;
  String _recognizedText = '';
  List<String> _numbersOnly = [];

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isNotEmpty) {
        _cameraController = CameraController(
          cameras.first,
          ResolutionPreset.high,
          enableAudio: false,
        );

        await _cameraController!.initialize();
        _textRecognizer = TextRecognizer();
        
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      print('Error initializing camera: $e');
    }
  }

  Future<void> _processImage() async {
    if (_cameraController == null || _textRecognizer == null || _isProcessing) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final XFile image = await _cameraController!.takePicture();
      final inputImage = InputImage.fromFilePath(image.path);
      
      final recognizedText = await _textRecognizer!.processImage(inputImage);
      
      // Lọc chỉ lấy số
      final numbersOnly = <String>[];
      for (final block in recognizedText.blocks) {
        for (final line in block.lines) {
          final text = line.text;
          // Chỉ lấy dòng có toàn số
          if (RegExp(r'^\d+$').hasMatch(text.trim())) {
            numbersOnly.add(text.trim());
          }
        }
      }

      setState(() {
        _recognizedText = recognizedText.text;
        _numbersOnly = numbersOnly;
      });

      // Nếu tìm thấy số, trả về số đầu tiên
      if (numbersOnly.isNotEmpty) {
        Navigator.pop(context, numbersOnly.first);
      } else {
        // Hiển thị dialog không tìm thấy số
        _showNoNumbersDialog();
      }
    } catch (e) {
      print('Error processing image: $e');
      _showErrorDialog('Lỗi khi xử lý ảnh: $e');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  void _showNoNumbersDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Không tìm thấy số'),
        content: const Text('Không tìm thấy số nào trong ảnh. Vui lòng thử lại.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Thử lại'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Hủy'),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Lỗi'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _textRecognizer?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quét Text (Chỉ số)', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          // Camera preview
          SizedBox(
            width: double.infinity,
            height: double.infinity,
            child: CameraPreview(_cameraController!),
          ),
          
          // Overlay với khung quét
          Center(
            child: Container(
              width: MediaQuery.of(context).size.width * 0.8,
              height: 100,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.red, width: 2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Text(
                  'Đặt số cần quét trong khung này',
                  style: TextStyle(
                    color: Colors.white,
                    backgroundColor: Colors.black54,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ),
          
          // Nút chụp ảnh
          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Center(
              child: FloatingActionButton(
                onPressed: _isProcessing ? null : _processImage,
                backgroundColor: _isProcessing ? Colors.grey : Colors.blue,
                child: _isProcessing 
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Icon(Icons.camera_alt, color: Colors.white),
              ),
            ),
          ),
          
          // Hiển thị kết quả nhận dạng
          if (_recognizedText.isNotEmpty)
            Positioned(
              top: 100,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Kết quả nhận dạng:',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _recognizedText,
                      style: const TextStyle(color: Colors.white),
                    ),
                    if (_numbersOnly.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Số tìm thấy:',
                        style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                      ),
                      ..._numbersOnly.map((number) => Text(
                        '• $number',
                        style: const TextStyle(color: Colors.green),
                      )),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
