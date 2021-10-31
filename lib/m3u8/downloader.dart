import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:m3u8_downloader/common/http.dart';
import 'package:m3u8_downloader/m3u8/entity.dart';
import 'package:m3u8_downloader/m3u8/parser.dart';
import 'package:encrypt/encrypt.dart';

final _logger = Logger('m3u8.downloader');

final httpRegExp = RegExp('https?://');

class M3U8Downloader {
  String url;
  String path;
  String name;
  int parallelism;
  late String urlPrefix;
  late M3U8 m3u8;
  late M3U8Encrypt? m3u8Encrypt;

  M3U8Downloader._(this.url, this.path, this.name, this.parallelism);

  static Future<M3U8Downloader> create(String url,
      {String path = '', String? name, int parallelism = 5}) async {
    if (!url.startsWith(httpRegExp) || !url.endsWith('.m3u8')) {
      throw M3U8Exception('invalid url');
    }
    var m3u8Downloader = M3U8Downloader._(url, path,
        name ?? DateTime.now().millisecondsSinceEpoch.toString(), parallelism);
    m3u8Downloader.urlPrefix =
        url.split(Uri.parse(url).pathSegments.last).first;
    m3u8Downloader.m3u8 = await _buildM3U8(url);
    if (!_checkM3U8(m3u8Downloader.m3u8)) {
      throw M3U8Exception('invalid m3u8');
    }
    return m3u8Downloader;
  }

  Future<void> download() async {
    m3u8Encrypt = m3u8.key == null ? null : await _buildEncrypt(m3u8.key!);
    var dir = Directory('$path/$name');
    if (!(await dir.exists())) {
      await dir.create();
    }

    var indexes = List<List<int>>.generate(parallelism, (i) {
      return [for (var j = i; j < m3u8.segments.length; j += parallelism) j];
    });

    _logger.info('[${Isolate.current.debugName}] start download');
    var completers = <Completer>[];
    var receivePorts = <ReceivePort>[];
    for (var segments in indexes) {
      var completer = Completer();
      completers.add(completer);
      var receivePort = ReceivePort();
      receivePorts.add(receivePort);
      await Isolate.spawn<M3U8DownloadTask>(_isolateDownload,
          M3U8DownloadTask(segments, receivePort.sendPort, this));
      receivePort.listen((result) {
        if (result as bool) {
          _logger.info('[${Isolate.current.debugName}] finish');
          completer.complete();
          receivePort.close();
        } else {
          throw M3U8Exception('unknown message');
        }
      });
    }
    _logger.info('[${Isolate.current.debugName}] waiting download finish');
    await Future.wait(completers.map((c) => c.future).toList());
  }

  Future<void> merge() async {
    var file = File('$path/$name/main.ts');
    for (var segment in m3u8.segments) {
      _logger.info('merging ${segment.uri}');
      var ts = File('$path/$name/${segment.uri}');
      if (await ts.exists()) {
        await file.writeAsBytes(await ts.readAsBytes(), mode: FileMode.append);
      } else {
        throw M3U8Exception('no such ts segment');
      }
    }
  }

  static Future<void> _isolateDownload(M3U8DownloadTask task) async {
    for (var i in task.indexes) {
      await _download(
          task.m3u8Downloader.m3u8.segments[i],
          task.m3u8Downloader.path,
          task.m3u8Downloader.name,
          task.m3u8Downloader.urlPrefix,
          task.m3u8Downloader.m3u8Encrypt);
    }
    task.sendPort.send(true);
  }

  static Future<void> _download(M3U8Segment segment, String path, String name,
      String urlPrefix, M3U8Encrypt? m3u8Encrypt) async {
    _logger.info('[${Isolate.current.debugName}] downloading ${segment.uri}');
    var tsUri = segment.uri!.startsWith(httpRegExp)
        ? segment.uri!
        : urlPrefix + segment.uri!;
    var data = await decrypt(await getBytes(tsUri), m3u8Encrypt);
    var tsFile = File('$path/$name/${Uri.parse(tsUri).pathSegments.last}');
    if (await tsFile.exists()) {
      _logger.info('[${Isolate.current.debugName}] skip ${segment.uri}');
      return;
    }
    await tsFile.writeAsBytes(data);
  }

  static Future<Uint8List> decrypt(
      Uint8List data, M3U8Encrypt? m3u8Encrypt) async {
    if (m3u8Encrypt == null) {
      return data;
    }
    var decryptBytes = m3u8Encrypt.encrypter.decryptBytes(Encrypted(data),
        iv: m3u8Encrypt.iv == null ? null : IV(m3u8Encrypt.iv!));
    return Uint8List.fromList(decryptBytes);
  }

  static Future<M3U8> _buildM3U8(String url) async {
    var body = await get(url);
    return parse(body);
  }

  Future<M3U8Encrypt> _buildEncrypt(M3U8Key keySegment) async {
    if (keySegment.method == 'AES-128') {
      var key = await getBytes(keySegment.url!.startsWith(httpRegExp)
          ? keySegment.url!
          : urlPrefix + keySegment.url!);
      var iv = keySegment.iv == null
          ? null
          : decodeHexString(keySegment.iv!.startsWith('0x')
              ? keySegment.iv!.substring(2)
              : keySegment.iv!);
      var encrypter = Encrypter(AES(Key(key), mode: AESMode.cbc));
      return M3U8Encrypt(keySegment.method!, key, iv, encrypter);
    } else {
      throw M3U8Error('nonsupport encrypt method');
    }
  }

  static bool _checkM3U8(M3U8 m3u8) {
    if (!m3u8.m3u) {
      return false;
    }
    for (var segment in m3u8.segments) {
      if (segment.uri == null || segment.duration == null) {
        return false;
      }
    }
    return true;
  }
}

class M3U8DownloadTask {
  M3U8Downloader m3u8Downloader;
  List<int> indexes;
  SendPort sendPort;

  M3U8DownloadTask(this.indexes, this.sendPort, this.m3u8Downloader);
}

class M3U8Encrypt {
  String method;
  Uint8List key;
  Uint8List? iv;
  Encrypter encrypter;

  M3U8Encrypt(this.method, this.key, this.iv, this.encrypter);
}

class M3U8Error extends Error {
  final String message;

  M3U8Error(this.message);
}

class M3U8Exception implements Exception {
  String message;

  M3U8Exception(this.message);
}
