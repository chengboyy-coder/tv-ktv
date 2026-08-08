import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:video_player/video_player.dart';
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
  final String videoUrl; // MV 视频播放地址

  SongItem({
    required this.title,
    required this.artist,
    required this.videoUrl,
  });
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

  VideoPlayerController? _videoController;
  bool _isVideoLoading = false;

  final TextEditingController _searchController = TextEditingController();

  // 内置示范曲库（使用开放的示例 MP4 MP3 测试视频链接）
  final List<SongItem> _mockMusicLibrary = [
    SongItem(
      title: '海阔天空',
      artist: 'Beyond',
      videoUrl: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
    ),
    SongItem(
      title: '光辉岁月',
      artist: 'Beyond',
      videoUrl: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4',
    ),
    SongItem(
      title: '恭喜发财',
      artist: '刘德华',
      videoUrl: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4',
    ),
    SongItem(
      title: '七里香',
      artist: '周杰伦',
      videoUrl: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4',
    ),
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

  void _playSong(SongItem song) async {
    setState(() {
      _currentSong = song;
      _isVideoLoading = true;
    });

    await _videoController?.dispose();
    _videoController = VideoPlayerController.networkUrl(Uri.parse(song.videoUrl));

    try {
      await _videoController!.initialize();
      _videoController!.play();
      _videoController!.addListener(() {
        // 播放结束自动切换下一首
        if (_videoController!.value.position >= _videoController!.value.duration &&
            !_videoController!.value.isPlaying) {
          _nextSong();
        }
      });
    } catch (e) {
      debugPrint('视频加载播放失败: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isVideoLoading = false;
        });
      }
    }
  }

  void _handleClientMessage(dynamic message) {
    try {
      var data = jsonDecode(message.toString());
      if (data['action'] == 'add_song') {
        var song = SongItem(
          title: data['title'] ?? '未知歌曲',
          artist: data['artist'] ?? '群星',
          videoUrl: data['videoUrl'] ?? 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
        );
        _addSongToPlaylist(song);
      }
    } catch (_) {}
  }

  void _addSongToPlaylist(SongItem song) {
    setState(() {
      if (_currentSong == null) {
        _playSong(song);
      } else {
        _playlist.add(song);
      }
    });
  }

  void _nextSong() {
    if (_playlist.isNotEmpty) {
      var next = _playlist.removeAt(0);
      _playSong(next);
    } else {
      _videoController?.dispose();
      _videoController = null;
      setState(() {
        _currentSong = null;
      });
    }
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
    <title>KTV 手机点歌台</title>
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
            {title: '海阔天空', artist: 'Beyond', videoUrl: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4'},
            {title: '光辉岁月', artist: 'Beyond', videoUrl: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4'},
            {title: '恭喜发财', artist: '刘德华', videoUrl: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4'},
            {title: '七里香', artist: '周杰伦', videoUrl: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4'}
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
                    <button class="add-btn" onclick="sendSong('\${song.title}', '\${song.artist}', '\${song.videoUrl}')">点歌</button>
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

        function sendSong(title, artist, videoUrl) {
            if (ws && ws.readyState === WebSocket.OPEN) {
                ws.send(JSON.stringify({ action: 'add_song', title: title, artist: artist, videoUrl: videoUrl }));
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
    _videoController?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String connectUrl = 'http://$_localIp:$_port';

    return Scaffold(
      body: Stack(
        children: [
          // 背景 MV 视频播放层
          if (_videoController != null && _videoController!.value.isInitialized)
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _videoController!.value.size.width,
                  height: _videoController!.value.size.height,
                  child: VideoPlayer(_videoController!),
                ),
              ),
            )
          else
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF2C004D), Color(0xFF140029)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),

          // 蒙版半透明遮罩（防止背景视频太亮影响看清UI）
          Container(color: Colors.black.withOpacity(0.4)),

          // 前景 UI 控制层
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Row(
                  children: [
                    Text(
                      '当前播放: ${_currentSong?.title ?? "等待点歌..."} ${_currentSong != null ? "(${_currentSong!.artist})" : ""}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.cyanAccent),
                    ),
                    const SizedBox(width: 20),
                    Text(
                      '已点歌曲: ${_playlist.length} 首',
                      style: const TextStyle(fontSize: 16, color: Colors.white70),
                    ),
                    if (_isVideoLoading) ...[
                      const SizedBox(width: 15),
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.pinkAccent),
                      ),
                      const SizedBox(width: 6),
                      const Text('加载MV中...', style: TextStyle(fontSize: 13, color: Colors.pinkAccent)),
                    ],
                    const Spacer(),
                    const Icon(Icons.wifi, color: Colors.greenAccent),
                  ],
                ),
              ),

              Expanded(
                child: Row(
                  children: [
                    // 左侧：电视端搜索与点歌区
                    Expanded(
                      flex: 5,
                      child: Container(
                        margin: const EdgeInsets.only(left: 16, bottom: 16, right: 8),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Column(
                          children: [
                            TextField(
                              controller: _searchController,
                              onChanged: _filterTvSongs,
                              decoration: InputDecoration(
                                hintText: '🔍 输入歌名或歌手...',
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

                    // 右侧：二维码与控制面板
                    Expanded(
                      flex: 5,
                      child: Container(
                        margin: const EdgeInsets.only(right: 16, bottom: 16, left: 8),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.6),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                children: [
                                  if (!_localIp.startsWith('正在'))
                                    QrImageView(
                                      data: connectUrl,
                                      version: QrVersions.auto,
                                      size: 140.0,
                                      backgroundColor: Colors.white,
                                    )
                                  else
                                    const CircularProgressIndicator(),
                                  const SizedBox(height: 10),
                                  const Text('📱 扫码点歌', style: TextStyle(fontSize: 14)),
                                  Text(
                                    connectUrl,
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.cyanAccent),
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
                                      // 控制音量模拟原/伴唱（如果有声道控制也可以在此扩展）
                                      _videoController?.setVolume(_isAccompany ? 0.3 : 1.0);
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
