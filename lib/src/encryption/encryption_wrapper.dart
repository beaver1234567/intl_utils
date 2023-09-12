import 'package:intl_utils/src/encryption/encryption_config.dart';
import 'package:intl_utils/src/encryption/encryption_helper.dart';

class EncryptionWrapper {

  final EncryptionHelper? _helper;

  EncryptionWrapper(this._helper);

  String? get encodedKey => _helper?.encodedKey;
  String? get encodedIv => _helper?.encodedIv;

  static Future<EncryptionWrapper> fromConfig(EncryptionConfig? config) async {
    final enabled = config != null && config.enabled == true;

    if (enabled) {
      final helper = await EncryptionHelper.create(config.key!);
      return EncryptionWrapper(helper);
    }

    return EncryptionWrapper(null);
  }

  Future<String?> wrap(String? value) async {
    final helper = _helper;
    if (helper == null) {
      return value;
    }
    if (value == null) {
      return null;
    }
    return await helper.encrypt64(value);
  }
}