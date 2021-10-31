extension EnumExtension on Enum {
  String name() {
    return toString().split('.').last;
  }
}
