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
  final String videoUrl;

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
  String? _playErrorMsg;

  // 使用兼容量最高的高清通用 MP4 测试源
  final List<SongItem> _mockMusicLibrary = [
    SongItem(
      title: '海阔天空 (KTV高清版)',
      artist: 'Beyond',
      videoUrl: 'https://media.w3.org/2010/05/sintel/trailer.mp4',
    ),
    SongItem(
      title: '光辉岁月 (KTV高清版)',
      artist: 'Beyond',
      videoUrl: 'https://www.w3schools.com/html/mov_bbb.mp4',
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
      String foundIp = '';
      try {
        var interfaces = await NetworkInterface.list(
          includeLoopback: false,
          type: InternetAddressType.IPv4,
        );
        for (var interface in interfaces) {
          for (var addr in interface.addresses) {
            if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
              if (!addr.address.startsWith('169.254')) {
                foundIp = addr.address;
                break;
              }
            }
          }
          if (foundIp.isNotEmpty) break;
        }
      } catch (e) {
        debugPrint('获取IP失败: $e');
      }

      setState(() {
        _localIp = foundIp.isNotEmpty ? foundIp : '请检查 Wi-Fi 连接';
      });

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
    } catch (e) {
      debugPrint('服务器启动失败: $e');
    }
  }

  void _playSong(SongItem song) async {
    setState(() {
      _currentSong = song;
      _isVideoLoading = true;
      _playErrorMsg = null;
    });

    if (_videoController != null) {
      await _videoController!.pause();
      await _videoController!.dispose();
      _videoController = null;
    }

    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(song.videoUrl),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );

      _videoController = controller;
      await controller.initialize();
      
      if (!mounted) return;

      setState(() {
        _isVideoLoading = false;
      });

      controller.play();
      controller.setLooping(false);
      
      controller.addListener(() {
        if (controller.value.hasError) {
          if (mounted) {
            setState(() {
              _playErrorMsg = '视频解码失败，换一首试试';
              _isVideoLoading = false;
            });
          }
        }
        if (controller.value.isInitialized &&
            controller.value.position >= controller.value.duration &&
            !controller.value.isPlaying) {
          _nextSong();
        }
      });
    } catch (e) {
      debugPrint('视频加载失败: $e');
      if (mounted) {
        setState(() {
          _isVideoLoading = false;
          _playErrorMsg = '视频播放失败: $e';
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
          artist: data['artist'] ?? 'B站视频',
          videoUrl: data['videoUrl'] ?? '',
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
        _playErrorMsg = null;
      });
    }
  }

  String _getMobileHtmlPage() {
    return '''
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <title>KTV 全网点歌台</title>
    <style>
        body { font-family: -apple-system, sans-serif; background: #120024; color: white; margin: 0; padding: 15px; }
        .search-box { display: flex; gap: 8px; margin-bottom: 15px; }
        input { flex: 1; padding: 12px 16px; border-radius: 25px; border: none; background: rgba(255,255,255,0.15); color: white; font-size: 16px; outline: none; }
        input::placeholder { color: #aaa; }
        button.search-btn { background: #ff007f; color: white; border: none; padding: 0 18px; border-radius: 20px; font-weight: bold; cursor: pointer; }
        .song-list { display: flex; flex-direction: column; gap: 10px; }
        .song-card { background: rgba(255,255,255,0.08); padding: 12px 16px; border-radius: 12px; display: flex; justify-content: space-between; align-items: center; }
        .song-title { font-size: 15px; font-weight: bold; margin-bottom: 4px; overflow: hidden; text-overflow: ellipsis; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; }
        .song-artist { font-size: 12px; color: #00f2fe; }
        .add-btn { background: linear-gradient(135deg, #00c6ff, #0072ff); color: white; border: none; padding: 8px 16px; border-radius: 20px; font-weight: bold; cursor: pointer; white-space: nowrap; }
        .status { text-align: center; color: #00f2fe; margin-bottom: 12px; font-size: 13px; }
        .loading { text-align: center; color: #aaa; margin-top: 20px; }
    </style>
</head>
<body>
    <div id="msg" class="status">正在连接电视...</div>
    <div class="search-box">
        <input type="text" id="searchInput" placeholder="🔍 搜索任意歌曲/歌手 + KTV..." onkeypress="handleKeyPress(event)">
        <button class="search-btn" onclick="searchBilibili()">搜索</button>
    </div>
    <div id="songList" class="song-list"></div>

    <script>
        let ws;
        function connect() {
            const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
            ws = new WebSocket(protocol + '//' + window.location.host);
            ws.onopen = () => { document.getElementById('msg').innerText = '✅ 已连接电视点歌台'; };
            ws.onclose = () => { setTimeout(connect, 1000); };
        }
        connect();

        function handleKeyPress(e) {
            if (e.key === 'Enter') searchBilibili();
        }

        async function searchBilibili() {
            const kw = document.getElementById('searchInput').value.trim();
            if (!kw) return;
            const container = document.getElementById('songList');
            container.innerHTML = '<div class="loading">正在全网搜索 B站 KTV 资源...</div>';

            try {
                const query = encodeURIComponent(kw + ' KTV');
                const res = await fetch('https://api.allorigins.win/get?url=' + encodeURIComponent('https://api.bilibili.com/x/web-interface/wbi/search/type?search_type=video&keyword=' + query));
                const rawData = await res.json();
                const data = JSON.parse(rawData.contents);

                if (data && data.data && data.data.result) {
                    container.innerHTML = '';
                    const list = data.data.result.slice(0, 15);
                    list.forEach(item => {
                        const title = item.title.replace(/<[^>]+>/g, '');
                        const author = item.author;
                        const bvid = item.bvid;

                        const card = document.createElement('div');
                        card.className = 'song-card';
                        card.innerHTML = `
                            <div style="flex: 1; margin-right: 10px;">
                                <div class="song-title">\${title}</div>
                                <div class="song-artist">UP主: \${author}</div>
                            </div>
                            <button class="add-btn" onclick="parseAndSend('\${bvid}', '\${title.replace(/'/g, "")}', '\${author}')">点歌</button>
                        `;
                        container.appendChild(card);
                    });
                } else {
                    container.innerHTML = '<div class="loading">未搜索到相关 KTV 视频，请尝试搜索其他关键词</div>';
                }
            } catch (err) {
                container.innerHTML = '<div class="loading">搜索失败，请检查手机网络连接</div>';
            }
        }

        async function parseAndSend(bvid, title, author) {
            alert('正在解析视频《' + title + '》，请稍候...');
            try {
                const res = await fetch('https://api.allorigins.win/get?url=' + encodeURIComponent('https://api.bilibili.com/x/web-interface/view?bvid=' + bvid));
                const rawData = await res.json();
                const data = JSON.parse(rawData.contents);
                const cid = data.data.cid;

                const streamRes = await fetch('https://api.allorigins.win/get?url=' + encodeURIComponent('https://api.bilibili.com/x/player/playurl?bvid=' + bvid + '&cid=' + cid + '&qn=32&type=mp4&platform=html5'));
                const streamRaw = await streamRes.json();
                const streamData = JSON.parse(streamRaw.contents);

                if (streamData && streamData.data && streamData.data.durl) {
                    const videoUrl = streamData.data.durl[0].url;
                    if (ws && ws.readyState === WebSocket.OPEN) {
                        ws.send(JSON.stringify({
                            action: 'add_song',
                            title: title,
                            artist: author,
                            videoUrl: videoUrl
                        }));
                        alert('✅ 点歌成功！已加入电视播放队列');
                    }
                } else {
                    alert('该视频格式暂不支持播放，请选择列表中其他视频');
                }
            } catch (e) {
                alert('视频解析失败，请重试');
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
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String connectUrl = _localIp.contains('.') ? 'http://$_localIp:$_port' : '';

    return Scaffold(
      body: Stack(
        children: [
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

          Container(color: Colors.black.withOpacity(0.35)),

          Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '当前播放: ${_currentSong?.title ?? "等待手机扫码点歌..."}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.cyanAccent),
                      ),
                    ),
                    const SizedBox(width: 10),
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
                      const Text('加载视频中...', style: TextStyle(fontSize: 13, color: Colors.pinkAccent)),
                    ],
                    if (_playErrorMsg != null) ...[
                      const SizedBox(width: 15),
                      Text(_playErrorMsg!, style: const TextStyle(fontSize: 13, color: Colors.orangeAccent)),
                    ]
                  ],
                ),
              ),

              Expanded(
                child: Row(
                  children: [
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
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '📺 电视端预设/本地曲库',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.pinkAccent),
                            ),
                            const SizedBox(height: 10),
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
                                  if (connectUrl.isNotEmpty)
                                    QrImageView(
                                      data: connectUrl,
                                      version: QrVersions.auto,
                                      size: 140.0,
                                      backgroundColor: Colors.white,
                                    )
                                  else
                                    const SizedBox(
                                      height: 140,
                                      child: Center(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            CircularProgressIndicator(),
                                            SizedBox(height: 10),
                                            Text('正在获取局域网IP...', style: TextStyle(fontSize: 12, color: Colors.white54)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  const SizedBox(height: 10),
                                  const Text('📱 扫码打开手机全网点歌台', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                  Text(
                                    connectUrl.isNotEmpty ? connectUrl : 'IP获取中，请确认连同一Wi-Fi',
                                    style: const TextStyle(fontSize: 13, color: Colors.cyanAccent),
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
                                      _videoController?.setVolume(_isAccompany ? 0.2 : 1.0);
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
