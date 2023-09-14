import 'package:yaml/yaml.dart' as yaml;

class FlutterConfig {
  final List<String>? _assets;

  FlutterConfig(this._assets);

  List<String> get assets => _assets ?? [];

  static FlutterConfig fromConfig(yaml.YamlMap? flutterConfig) {
    if (flutterConfig == null) {
      return FlutterConfig([]);
    }
    final assets = flutterConfig['assets'];
    if (assets == null) {
      return FlutterConfig([]);
    }
    final items = <String>[];
    for (final element in assets) {
      if (element is String) {
        items.add(element);
      }
    }
    return FlutterConfig(items);
  }
}