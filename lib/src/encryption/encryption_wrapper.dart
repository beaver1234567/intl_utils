import 'dart:convert';

import 'package:intl_utils/src/encryption/encryption_config.dart';
import 'package:intl_utils/src/encryption/encryption_helper.dart';

import 'package:encrypt/encrypt.dart' as encrypt;

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

  String wrapValue(String value) {
    if (_helper == null) {
      return value;
    }

    if (encodedIv == null || encodedKey == null) {
      return value;
    }
    if (value.isEmpty) {
      return "";
    }

    final key = encrypt.Key.fromBase64(encodedKey!);
    final iv = encrypt.IV.fromBase64(encodedIv!);
    final cipher = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc, padding: 'PKCS7'));
    final result = cipher.encrypt(value, iv: iv);
    return result.base64;
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