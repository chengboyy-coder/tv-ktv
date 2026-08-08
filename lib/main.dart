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

  final TextEditingController _searchController = TextEditingController();
  final List<SongItem> _mockMusicLibrary = [
    SongItem(title: '海阔天空', artist: 'Beyond'),
    SongItem(title: '光辉岁月', artist: 'Beyond'),
    SongItem(title: '恭喜发财', artist: '刘德华'),
    SongItem(title: '冰雨', artist: '刘德华'),
    SongItem(title: '七里香', artist: '周杰伦'),
    SongItem(title: '晴天', artist: '周杰伦'),
    SongItem(title: '稻香', artist: '周杰伦'),
    SongItem(title: '后来', artist: '刘若英'),
    SongItem(title: '十年', artist: '陈奕迅'),
    SongItem(title: '孤勇者', artist: '陈奕迅'),
  ];
  List<SongItem> _tvSearchResults = [];

  @override
  void initState() {
    super.initState();
    _tvSearchResults = List.from(_mockMusicLibrary);
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
        _addSongToPlaylist(SongItem(
          title: data['title'] ?? '未知歌曲',
          artist: data['artist'] ?? '群星',
        ));
      }
    } catch (_) {}
  }

  void _addSongToPlaylist(SongItem song) {
    setState(() {
      _playlist.add(song);
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

  void _filterTvSongs(String keyword) {
    setState(() {
      if (keyword.isEmpty) {
        _tvSearchResults = List.from(_mockMusicLibrary);
      } else {
        _tvSearchResults = _mockMusicLibrary
            .where((song) =>
                song.title.contains(keyword) || song.artist.contains(keyword))
            .toList();
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
    <title>KTV 手机搜索点歌台</title>
    <style>
        body { font-family: -apple-system, sans-serif; background: #120024; color: white; margin: 0; padding: 15px; }
        .search-box { display: flex; gap: 8px; margin-bottom: 15px; }
        input { flex: 1; padding: 12px 16px; border-radius: 25px; border: none; background: rgba(255,255,255,0.15); color: white; font-size: 16px; outline: none; }
        input::placeholder { color: #aaa; }
        .song-list { display: flex; flex-direction: column; gap: 10px; }
        .song-card { background: rgba(255,255,255,0.08); padding: 12px 16px; border-radius: 12px; display: flex; justify-content: space-between; align-items: center; }
        .song-title { font-size: 16px; font-weight: bold; margin-bottom: 4px; }
        .song-artist { font-size: 13px; color: #aaa; }
        .add-btn { background: linear-gradient(135deg, #ff007f, #7928ca); color: white; border: none; padding: 8px 18px; border-radius: 20px; font-weight: bold; cursor: pointer; }
        .status { text-align: center; color: #00f2fe; margin-bottom: 12px; font-size: 13px; }
    </style>
</head>
<body>
    <div id="msg" class="status">正在连接电视...</div>
    <div class="search-box">
        <input type="text" id="searchInput" placeholder="🔍 搜索歌曲或歌手..." oninput="doSearch()">
    </div>
    <div class="song-list" id="songList"></div>

    <script>
        const songs = [
            {title: '海阔天空', artist: 'Beyond'},
            {title: '光辉岁月', artist: 'Beyond'},
            {title: '恭喜发财', artist: '刘德华'},
            {title: '冰雨', artist: '刘德华'},
            {title: '七里香', artist: '周杰伦'},
            {title: '晴天', artist: '周杰伦'},
            {title: '稻香', artist: '周杰伦'},
            {title: '后来', artist: '刘若英'},
            {title: '十年', artist: '陈奕迅'},
            {title: '孤勇者', artist: '陈奕迅'}
        ];

        let ws;
        function connect() {
            const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
            ws = new WebSocket(protocol + '//' + window.location.host);
            ws.onopen = () => { document.getElementById('msg').innerText = '✅ 已连接电视点歌台'; };
            ws.onclose = () => { setTimeout(connect, 1000); };
        }
        connect();

        function renderSongs(list) {
            const container = document.getElementById('songList');
            container.innerHTML = '';
            list.forEach(song => {
                const item = document.createElement('div');
                item.className = 'song-card';
                item.innerHTML = `
                    <div>
                        <div class="song-title">\${song.title}</div>
                        <div class="song-artist">\${song.artist}</div>
                    </div>
                    <button class="add-btn" onclick="sendSong('\${song.title}', '\${song.artist}')">点歌</button>
                `;
                container.appendChild(item);
            });
        }

        function doSearch() {
            const kw = document.getElementById('searchInput').value.trim().toLowerCase();
            if (!kw) { renderSongs(songs); return; }
            const filtered = songs.filter(s => s.title.toLowerCase().includes(kw) || s.artist.toLowerCase().includes(kw));
            renderSongs(filtered);
        }

        function sendSong(title, artist) {
            if (ws && ws.readyState === WebSocket.OPEN) {
                ws.send(JSON.stringify({ action: 'add_song', title: title, artist: artist }));
                alert('已成功点歌：《' + title + '》');
            } else {
                alert('网络连接中，请稍后再试');
            }
        }

        renderSongs(songs);
    </script>
</body>
</html>
''';
  }

  @override
  void dispose() {
    _server?.close();
    _searchController.dispose();
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
              // 顶栏状态
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Row(
                  children: [
                    Text(
                      '当前播放: ${_currentSong?.title ?? "暂无播放"} (${_currentSong?.artist ?? "无"})',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.cyanAccent),
                    ),
                    const SizedBox(width: 20),
                    Text(
                      '已点歌曲: ${_playlist.length} 首',
                      style: const TextStyle(fontSize: 16, color: Colors.white70),
                    ),
                    const Spacer(),
                    const Icon(Icons.wifi, color: Colors.greenAccent),
                  ],
                ),
              ),

              Expanded(
                child: Row(
                  children: [
                    // 左侧：电视端键盘/搜歌区
                    Expanded(
                      flex: 6,
                      child: Container(
                        margin: const EdgeInsets.only(left: 16, bottom: 16, right: 8),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.black38,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Column(
                          children: [
                            TextField(
                              controller: _searchController,
                              onChanged: _filterTvSongs,
                              decoration: InputDecoration(
                                hintText: '🔍 电视端搜索：输入歌名或歌手...',
                                prefixIcon: const Icon(Icons.search, color: Colors.pinkAccent),
                                filled: true,
                                fillColor: Colors.white10,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(30),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Expanded(
                              child: ListView.builder(
                                itemCount: _tvSearchResults.length,
                                itemBuilder: (context, index) {
                                  final song = _tvSearchResults[index];
                                  return ListTile(
                                    title: Text(song.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                                    subtitle: Text(song.artist, style: const TextStyle(color: Colors.white54)),
                                    trailing: ElevatedButton(
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.pinkAccent),
                                      onPressed: () => _addSongToPlaylist(song),
                                      child: const Text('点歌'),
                                    ),
                                  );
                                },
                              ),
                            )
                          ],
                        ),
                      ),
                    ),

                    // 右侧：扫码区与电视切歌面板
                    Expanded(
                      flex: 4,
                      child: Container(
                        margin: const EdgeInsets.only(right: 16, bottom: 16, left: 8),
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
                                      size: 150.0,
                                      backgroundColor: Colors.white,
                                    )
                                  else
                                    const CircularProgressIndicator(),
                                  const SizedBox(height: 10),
                                  const Text('📱 手机扫码搜索点歌', style: TextStyle(fontSize: 14)),
                                  Text(
                                    connectUrl,
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.cyanAccent),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
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
