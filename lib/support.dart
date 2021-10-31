enum VideoType {
  m3u8,
}

class NotSupportTypeError extends Error {
  String type;
  NotSupportTypeError(this.type);
}