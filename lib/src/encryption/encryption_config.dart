import 'package:yaml/yaml.dart' as yaml;

class EncryptionConfig {

  final bool enabled;
  final String? key;
  final bool verbose;

  EncryptionConfig({
    required this.enabled,
    this.key,
    required this.verbose
  });

  static EncryptionConfig? fromConfig(yaml.YamlMap? config) {
    if (config == null) {
      return null;
    }

    return EncryptionConfig(
      enabled: config['enabled'] == true,
      key: config['key'] is String ? config['key'] : null,
      verbose: config['verbose'] is bool ? config['verbose'] : false
    );
  }
}