import 'dart:convert';
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

  SongItem({required this.title, required this.artist});
}

class KtvHomeScreen extends StatefulWidget {
  const KtvHomeScreen({super.key});

  @override
  State<KtvHomeScreen> createState() => _KtvHomeScreenState();
}

class _KtvHomeScreenState extends State<KtvHomeScreen> {
  HttpServer? _server;
  String _localIp = '正在获取IP...';
  final int _port = 8080;
  final List<SongItem> _playlist = [];
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

      var cascade = shelf.Cascade().add(webSocketHandler((WebSocketChannel webSocket) {
        webSocket.stream.listen((message) {
          _handleClientMessage(message);
        });
      })).add((shelf.Request request) {
        return shelf.Response.ok(_getMobileHtmlPage(), headers: {
          'content-type': 'text/html; charset=utf-8',
          'Access-Control-Allow-Origin': '*',
        });
      });

      _server = await io.serve(cascade.handler, InternetAddress.anyIPv4, _port);
      setState(() {});
    } catch (e) {
      debugPrint('服务器启动失败: $e');
    }
  }

  void _handleClientMessage(dynamic message) {
    try {
      var data = jsonDecode(message.toString());
      if (data['action'] == 'add_song') {
        setState(() {
          _playlist.add(SongItem(
            title: data['title'] ?? '示范歌曲',
            artist: data['artist'] ?? '热门歌手',
          ));
          if (_currentSong == null && _playlist.isNotEmpty) {
            _currentSong = _playlist.removeAt(0);
          }
        });
      }
    } catch (_) {}
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
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <title>KTV 手机点歌台</title>
    <style>
        body { font-family: -apple-system, sans-serif; background: #1a0033; color: white; text-align: center; padding: 20px; margin: 0; }
        .card { background: rgba(255,255,255,0.1); padding: 20px; border-radius: 16px; margin-top: 20px; }
        button { background: linear-gradient(135deg, #ff007f, #7928ca); color: white; border: none; padding: 16px 32px; font-size: 18px; border-radius: 30px; font-weight: bold; width: 80%; cursor: pointer; box-shadow: 0 4px 15px rgba(255,0,127,0.4); margin: 10px 0; }
        button:active { transform: scale(0.98); }
        .status { color: #00f2fe; margin-top: 10px; font-size: 14px; }
    </style>
</head>
<body>
    <h2>🎤 点歌控制台</h2>
    <div class="card">
        <p>已连接电视：<strong>$_localIp</strong></p>
        <button onclick="sendSong('恭喜发财', '刘德华')">🎵 点歌：恭喜发财</button>
        <button onclick="sendSong('海阔天空', 'Beyond')" style="background: linear-gradient(135deg, #0070f3, #00dfd8);">🎵 点歌：海阔天空</button>
        <div id="msg" class="status">准备就绪</div>
    </div>
    <script>
        let ws;
        function connect() {
            const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
            ws = new WebSocket(protocol + '//' + window.location.host);
            ws.onopen = () => { document.getElementById('msg').innerText = '✅ 已实时连接到电视'; };
            ws.onclose = () => { setTimeout(connect, 1000); };
        }
        connect();

        function sendSong(title, artist) {
            if (ws && ws.readyState === WebSocket.OPEN) {
                ws.send(JSON.stringify({ action: 'add_song', title: title, artist: artist }));
                document.getElementById('msg').innerText = '🎉 《' + title + '》已发送到电视！';
            } else {
                alert('连接中，请稍后再试...');
            }
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

              Expanded(
                child: Row(
                  children: [
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

                    Expanded(
                      flex: 4,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white10,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              children: [
                                if (!_localIp.startsWith('正在'))
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
