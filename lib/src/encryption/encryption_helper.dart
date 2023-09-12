import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/helpers.dart';

class EncryptionHelper {

  final List<int> key;
  late List<int> iv;

  final algorithm = AesCbc.with256bits(macAlgorithm: Hmac.sha256());

  EncryptionHelper({required this.key}) {
    iv = algorithm.newNonce();
  }

  String get encodedKey => base64Encode(key);
  String get encodedIv => base64Encode(iv);

  Future<String> encrypt64(String value) async {
    final encrypted = await algorithm.encrypt(utf8.encode(value), secretKey: SecretKey(key), nonce: iv);
    return base64Encode(encrypted.cipherText);
  }

  static Future<EncryptionHelper> create(String key) async {
    final df = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 128, bits: 256);
    final secretKey = await df.deriveKeyFromPassword(password: key, nonce: randomBytes(32));
    return EncryptionHelper(key: await secretKey.extractBytes());
  }
}