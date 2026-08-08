import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const KtvTvApp());
}

class KtvTvApp extends StatelessWidget {
  const KtvTvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TV KTV',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF140029),
      ),
      home: const KtvHomeScreen(),
    );
  }
}

class SongItem {
  final String title;
  final String artist;
  final String url;

  SongItem({required this.title, required this.artist, required this.url});
}

class KtvHomeScreen extends StatefulWidget {
  const KtvHomeScreen({super.key});

  @override
  State<KtvHomeScreen> createState() => _KtvHomeScreenState();
}

class _KtvHomeScreenState extends State<KtvHomeScreen> {
  HttpServer? _server;
  String _localIp = '正在获取IP...';
  int _port = 8080;
  List<SongItem> _playlist = [];
  SongItem? _currentSong;
  bool _isAccompany = false;

  @override
  void initState() {
    super.initState();
    _initServer();
  }

  Future<void> _initServer() async {
    try {
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            _localIp = addr.address;
            break;
          }
        }
      }

      var handler = const shelf.Pipeline()
          .addMiddleware(shelf.logRequests())
          .addHandler((shelf.Request request) {
        if (request.url.path == 'ws') {
          return webSocketHandler((WebSocketChannel webSocket) {
            webSocket.stream.listen((message) {
              _handleClientMessage(message);
            });
          })(request);
        }
        return shelf.Response.ok(_getMobileHtmlPage(), headers: {
          'content-type': 'text/html; charset=utf-8',
        });
      });

      _server = await io.serve(handler, InternetAddress.anyIPv4, _port);
      setState(() {});
    } catch (e) {
      debugPrint('服务器启动失败: $e');
    }
  }

  void _handleClientMessage(dynamic message) {
    // 简易逻辑：解析手机端发来的点歌指令
    setState(() {
      _playlist.add(SongItem(
        title: '示范歌曲 ${DateTime.now().second}',
        artist: '热门歌手',
        url: '',
      ));
      if (_currentSong == null && _playlist.isNotEmpty) {
        _currentSong = _playlist.removeAt(0);
      }
    });
  }

  void _nextSong() {
    setState(() {
      if (_playlist.isNotEmpty) {
        _currentSong = _playlist.removeAt(0);
      } else {
        _currentSong = null;
      }
    });
  }

  String _getMobileHtmlPage() {
    return '''
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>KTV 手机点歌台</title>
    <style>
        body { font-family: sans-serif; background: #121212; color: white; text-align: center; padding: 20px; }
        button { background: #e91e63; color: white; border: none; padding: 15px 30px; font-size: 18px; border-radius: 25px; margin-top: 20px; cursor: pointer; }
    </style>
</head>
<body>
    <h2>🎤 欢迎使用 KTV 点歌台</h2>
    <p>已成功连接到客厅电视</p>
    <button onclick="requestSong()">点一首歌曲</button>
    <script>
        const ws = new WebSocket('ws://' + window.location.host + '/ws');
        function requestSong() {
            ws.send(JSON.stringify({action: 'add_song'}));
            alert('已成功点歌！');
        }
    </script>
</body>
</html>
''';
  }

  @override
  void dispose() {
    _server?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String connectUrl = 'http://$_localIp:$_port';

    return Scaffold(
      body: Stack(
        children: [
          // 背景高斯模糊/渐变
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF2C004D), Color(0xFF140029)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          Column(
            children: [
              // 顶部状态栏
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Row(
                  children: [
                    Text(
                      '当前: ${_currentSong?.title ?? "暂无播放"}  |  下首: ${_playlist.isNotEmpty ? _playlist.first.title : "未点歌"}',
                      style: const TextStyle(fontSize: 18, color: Colors.white70),
                    ),
                    const Spacer(),
                    const Icon(Icons.wifi, color: Colors.greenAccent),
                  ],
                ),
              ),

              // 主体区域
              Expanded(
                child: Row(
                  children: [
                    // 左侧视频播放窗口 (占位)
                    Expanded(
                      flex: 6,
                      child: Container(
                        margin: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.music_note, size: 80, color: Colors.pinkAccent),
                              const SizedBox(height: 16),
                              Text(
                                _currentSong != null ? _currentSong!.title : '等待点歌中...',
                                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                              ),
                              if (_currentSong != null)
                                Text(_currentSong!.artist, style: const TextStyle(fontSize: 20, color: Colors.white60)),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // 右侧控制面板与扫码区
                    Expanded(
                      flex: 4,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // 扫码点歌卡片
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white10,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              children: [
                                if (_localIp.startsWith('1'))
                                  QrImageView(
                                    data: connectUrl,
                                    version: QrVersions.auto,
                                    size: 160.0,
                                    backgroundColor: Colors.white,
                                  )
                                else
                                  const CircularProgressIndicator(),
                                const SizedBox(height: 12),
                                const Text('扫码/浏览器输入地址点歌:', style: TextStyle(fontSize: 14)),
                                Text(
                                  connectUrl,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.cyanAccent),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 30),

                          // 常用控制按钮组
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            alignment: WrapAlignment.center,
                            children: [
                              ElevatedButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _isAccompany = !_isAccompany;
                                  });
                                },
                                icon: Icon(_isAccompany ? Icons.subtitles_off : Icons.record_voice_over),
                                label: Text(_isAccompany ? '伴唱' : '原唱'),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
                              ),
                              ElevatedButton.icon(
                                onPressed: _nextSong,
                                icon: const Icon(Icons.skip_next),
                                label: const Text('切歌'),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.pinkAccent),
                              ),
                            ],
                          )
                        ],
                      ),
                    )
                  ],
                ),
              )
            ],
          )
        ],
      ),
    );
  }
}
