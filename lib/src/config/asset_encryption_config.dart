import 'package:yaml/yaml.dart' as yaml;

class AssetEncryptionConfig {

  final bool? _enabled;
  final String? _key;
  final String? _iv;
  final String? _magic;

  AssetEncryptionConfig(this._enabled, this._key, this._iv, this._magic);

  static AssetEncryptionConfig? fromConfig(yaml.YamlMap? config) {
   if (config == null) {
     return null;
   }

   final enabled = config['enabled'] != null && config['enabled'] is bool ? config['enabled'] : false;
   final iv = config['iv'];
   final key = config['key'];
   final magic = config['magic'];

   return AssetEncryptionConfig(enabled, key, iv, magic);
  }

  bool get enabled => _enabled ?? false;

  String? get key => enabled ? _key! : null;

  String? get iv => enabled ? _iv! : null;

  String? get magic => enabled ? _magic! : null;
}