import 'package:yaml/yaml.dart' as yaml;

class EncryptionConfig {

  final bool enabled;
  final String? key;

  EncryptionConfig({
    required this.enabled,
    this.key
  });

  static EncryptionConfig? fromConfig(yaml.YamlMap? config) {
    if (config == null) {
      return null;
    }

    return EncryptionConfig(
      enabled: config['enabled'] == true,
      key: config['key'] is String ? config['key'] : null
    );
  }
}