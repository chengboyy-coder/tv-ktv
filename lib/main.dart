import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const MaterialApp(home: KtvTvScreen()));
}

class KtvTvScreen extends StatefulWidget {
  const KtvTvScreen({super.key});

  @override
  State<KtvTvScreen> createState() => _KtvTvScreenState();
}

class _KtvTvScreenState extends State<KtvTvScreen> {
  late final player = Player();
  late final controller = VideoController(player);

  List<Map<String, String>> playlist = [];
  Map<String, String>? currentSong;
  String localIp = "127.0.0.1";
  bool isRightChannel = false;

  @override
  void initState() {
    super.initState();
    _startLocalServer();
    _listenPlayerEvents();
  }

  Future<void> _startLocalServer() async {
    for (var interface in await NetworkInterface.list()) {
      for (var addr in interface.addresses) {
        if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
          setState(() => localIp = addr.address);
          break;
        }
      }
    }

    var handler = webSocketHandler((webSocket) {
      webSocket.stream.listen((message) {
        final data = jsonDecode(message);
        if (data['action'] == 'add_song') {
          _addSong(data['title'], data['url']);
        } else if (data['action'] == 'next_song') {
          _playNext();
        } else if (data['action'] == 'toggle_channel') {
          _toggleChannel();
        }
      });
    });

    shelf_io.serve(handler, InternetAddress.anyIPv4, 8080);
  }

  void _addSong(String title, String url) {
    setState(() {
      playlist.add({'title': title, 'url': url});
    });
    if (currentSong == null) {
      _playNext();
    }
  }

  void _playNext() {
    if (playlist.isEmpty) {
      setState(() => currentSong = null);
      player.stop();
      return;
    }
    setState(() {
      currentSong = playlist.removeAt(0);
    });
    player.open(Media(currentSong!['url']!));
  }

  void _toggleChannel() {
    setState(() {
      isRightChannel = !isRightChannel;
    });
    player.setAudioBalance(isRightChannel ? 1.0 : 0.0);
  }

  void _listenPlayerEvents() {
    player.stream.completed.listen((completed) {
      if (completed) _playNext();
    });
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String qrUrl = "http://$localIp:8080";

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: currentSong != null
                ? Video(controller: controller)
                : const Text("暂无播放歌曲，请使用手机扫码点歌", style: TextStyle(color: Colors.white, fontSize: 24)),
          ),
          Positioned(
            top: 30,
            left: 30,
            child: Container(
              padding: const EdgeInsets.all(12),
              color: Colors.black54,
              child: Column(
                crossAxisAlignment: CrossAlignment.start,
                children: [
                  Text("正在播放: ${currentSong?['title'] ?? '无'}", style: const TextStyle(color: Colors.white, fontSize: 18)),
                  Text("已点数量: ${playlist.length}", style: const TextStyle(color: Colors.white70, fontSize: 14)),
                ],
              ),
            ),
          ),
          Positioned(
            top: 30,
            right: 30,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  QrImageView(data: qrUrl, size: 120),
                  Text("扫码点歌 ($localIp)", style: const TextStyle(fontSize: 10, color: Colors.black)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
