import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:m3u8_downloader/m3u8/entity.dart';
import 'package:m3u8_downloader/m3u8/tag.dart';

import 'downloader.dart';

final _logger = Logger('m3u8.parser');

M3U8 parse(String contents) {
  var m3u8 = M3U8();
  LineSplitter.split(contents).map((line) => line.trimLeft()).forEach((line) {
    if (line == '') {
      return;
    } else if (line.startsWith(EXTM3U)) {
      m3u8.m3u = true;
    } else if (line.startsWith(EXT_X_VERSION)) {
      m3u8.version = int.parse(line.split(':').last);
    } else if (line.startsWith(EXT_X_TARGETDURATION)) {
      m3u8.targetDuration = int.parse(line.split(':').last);
    } else if (line.startsWith(EXT_X_MEDIA_SEQUENCE)) {
      m3u8.mediaSequence = int.parse(line.split(':').last);
    } else if (line.startsWith(EXT_X_KEY)) {
      m3u8.key = parseKey(line);
    } else if (line.startsWith(EXTINF)) {
      m3u8.segments.add(M3U8Segment(double.parse(line.split(':').last.split(',').first)));
    } else if (line.startsWith(EXT_X_ENDLIST)) {
      m3u8.endList = true;
    } else if (line.startsWith('#')) {
      _logger.severe('unknown tag in m3u8, line: $line');
      throw M3U8Error('unknown or nonsupport tag');
    } else {
      if (m3u8.segments.isEmpty || m3u8.segments.last.uri != null) {
        _logger.severe('no suitable segment in m3u8, line: $line');
        throw M3U8Error('parse no suitable segment');
      }
      m3u8.segments.last.uri = line;
    }
  });
  return m3u8;
}

M3U8Key parseKey(String line) {
  var key = M3U8Key();
  line.split(':').last.split(',').forEach((value) {
    var split = value.split('=');
    if (split.length != 2) {
      _logger.severe('invalid filed in $EXT_X_KEY, line: $line');
      throw M3U8Error('parse $EXT_X_KEY fail');
    }
    if (split[0] == 'METHOD') {
      key.method = split[1];
    } else if (split[0] == 'URI') {
      if (split[1].startsWith('"') && split[1].endsWith('"')) {
        key.url = split[1].substring(1, split[1].length - 1);
      } else {
        key.url = split[1];
      }
    } else if (split[0] == 'IV') {
      key.iv = split[1];
    } else {
      _logger.severe('unknown field in $EXT_X_KEY, line: $line');
      throw M3U8Error('parse $EXT_X_KEY fail');
    }
  });
  return key;
}

