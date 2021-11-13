class M3U8 {
  String origin;
  bool m3u = false;
  int? version;
  int? targetDuration;
  int? mediaSequence;
  M3U8Key? key;
  List<M3U8Segment> segments = <M3U8Segment>[];
  bool? endList;

  M3U8(this.origin);

  bool isValid() {
    return m3u;
  }

  @override
  String toString() {
    return 'M3U8{m3u: $m3u, version: $version, targetDuration: $targetDuration, mediaSequence: $mediaSequence, key: $key, segments: $segments, endList: $endList}';
  }
}

class M3U8Key {
  String? method;
  String? url;
  String? iv;

  @override
  String toString() {
    return 'Key{method: $method, url: $url, iv: $iv}';
  }
}

class M3U8Segment {
  String? uri;
  double? duration;
  M3U8Segment(this.duration);

  @override
  String toString() {
    return 'Segment{uri: $uri, duration: $duration}';
  }
}