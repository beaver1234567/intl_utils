import 'dart:convert';
import 'dart:io';

import 'package:intl_utils/src/encryption/encryption_config.dart';
import 'package:intl_utils/src/encryption/encryption_wrapper.dart';

import '../config/pubspec_config.dart';
import '../constants/constants.dart';
import '../utils/file_utils.dart';
import '../utils/utils.dart';
import 'generator_exception.dart';
import 'intl_translation_helper.dart';
import 'label.dart';
import 'templates.dart';

/// The generator of localization files.
class Generator {
  late String _className;
  late String _mainLocale;
  late String _arbDir;
  late String _outputDir;
  late bool _useDeferredLoading;
  late bool _otaEnabled;
  late EncryptionConfig? _encryptionConfig;

  /// Creates a new generator with configuration from the 'pubspec.yaml' file.
  Generator() {
    var pubspecConfig = PubspecConfig();

    _className = defaultClassName;
    if (pubspecConfig.className != null) {
      if (isValidClassName(pubspecConfig.className!)) {
        _className = pubspecConfig.className!;
      } else {
        warning(
            "Config parameter 'class_name' requires valid 'UpperCamelCase' value.");
      }
    }

    _mainLocale = defaultMainLocale;
    if (pubspecConfig.mainLocale != null) {
      if (isValidLocale(pubspecConfig.mainLocale!)) {
        _mainLocale = pubspecConfig.mainLocale!;
      } else {
        warning(
            "Config parameter 'main_locale' requires value consisted of language code and optional script and country codes separated with underscore (e.g. 'en', 'en_GB', 'zh_Hans', 'zh_Hans_CN').");
      }
    }

    _arbDir = defaultArbDir;
    if (pubspecConfig.arbDir != null) {
      if (isValidPath(pubspecConfig.arbDir!)) {
        _arbDir = pubspecConfig.arbDir!;
      } else {
        warning(
            "Config parameter 'arb_dir' requires valid path value (e.g. 'lib', 'res/', 'lib\\l10n').");
      }
    }

    _outputDir = defaultOutputDir;
    if (pubspecConfig.outputDir != null) {
      if (isValidPath(pubspecConfig.outputDir!)) {
        _outputDir = pubspecConfig.outputDir!;
      } else {
        warning(
            "Config parameter 'output_dir' requires valid path value (e.g. 'lib', 'lib\\generated').");
      }
    }

    _useDeferredLoading =
        pubspecConfig.useDeferredLoading ?? defaultUseDeferredLoading;

    _otaEnabled =
        pubspecConfig.localizelyConfig?.otaEnabled ?? defaultOtaEnabled;

    _encryptionConfig = pubspecConfig.encryptionConfig;
  }

  /// Generates localization files.
  Future<void> generateAsync() async {
    var wrapper = await EncryptionWrapper.fromConfig(_encryptionConfig);

    await _updateL10nDir();
    await _updateGeneratedDir();
    await _generateWrappers(wrapper);
    await _generateDartFiles(wrapper);
  }

  Future<void> _generateWrappers(EncryptionWrapper wrapper) async {
    var fileName = "wrappers.dart";
    var file = File("$_outputDir/$fileName");

    final config = _encryptionConfig;
    final encodedKey = wrapper.encodedKey;
    final encodedIv = wrapper.encodedIv;
    if (config != null && config.enabled && encodedKey != null && encodedIv != null) {
      file.writeAsString("""
// hello world

import 'package:encrypt/encrypt.dart' as encrypt;
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:core';
import 'dart:typed_data';

const String encryptionKey = "$encodedKey";
const String encryptionIv = "$encodedIv";

String decryptString(String value) {
  final s = DateTime.now().microsecondsSinceEpoch;
  try {
    final key = encrypt.Key.fromBase64(encryptionKey);
    final iv = encrypt.IV.fromBase64(encryptionIv);
    final bytes = base64.decode(value);
    final cipher = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc, padding: 'PKCS7'));
    final decrypted = cipher.decryptBytes(encrypt.Encrypted(bytes), iv: iv);
    final ret = utf8.decode(decrypted);
    ${config.verbose ? 'print("decryptString time=\${DateTime.now().microsecondsSinceEpoch - s} length=\${value.length} ret=\${ret.length}");' : ''}
    return ret;
  } catch (e, s) {
    print("decryptString value=\$value failed");
    print("decryptString error \$e");
    print("\$s");
    rethrow;
  }
}

String k(String key) => decryptString(key);
  
String u(String value) => decryptString(value);
    """);
    } else {
      file.writeAsString("""
// hello world

String k(String key) => key;
  
String u(String value) => value;
    """);
    }
  }

  Future<void> _updateL10nDir() async {
    var mainArbFile = getArbFileForLocale(_mainLocale, _arbDir);
    if (mainArbFile == null) {
      await createArbFileForLocale(_mainLocale, _arbDir);
    }
  }

  Future<void> _updateGeneratedDir() async {
    var labels = _getLabelsFromMainArbFile();
    var locales = _orderLocales(getLocales(_arbDir));
    var content =
        generateL10nDartFileContent(_className, labels, locales, _otaEnabled);
    var formattedContent = formatDartContent(content, 'l10n.dart');

    await updateL10nDartFile(formattedContent, _outputDir);

    var intlDir = getIntlDirectory(_outputDir);
    if (intlDir == null) {
      await createIntlDirectory(_outputDir);
    }

    await removeUnusedGeneratedDartFiles(locales, _outputDir);
  }

  List<Label> _getLabelsFromMainArbFile() {
    var mainArbFile = getArbFileForLocale(_mainLocale, _arbDir);
    if (mainArbFile == null) {
      throw GeneratorException(
          "Can't find ARB file for the '$_mainLocale' locale.");
    }

    var content = mainArbFile.readAsStringSync();
    var decodedContent = json.decode(content) as Map<String, dynamic>;

    var labels =
        decodedContent.keys.where((key) => !key.startsWith('@')).map((key) {
      var name = key;
      var content = decodedContent[key];

      var meta = decodedContent['@$key'] ?? {};
      var type = meta['type'];
      var description = meta['description'];
      var placeholders = meta['placeholders'] != null
          ? (meta['placeholders'] as Map<String, dynamic>)
              .keys
              .map((placeholder) => Placeholder(
                  key, placeholder, meta['placeholders'][placeholder]))
              .toList()
          : null;

      return Label(name, content,
          type: type, description: description, placeholders: placeholders);
    }).toList();

    return labels;
  }

  List<String> _orderLocales(List<String> locales) {
    var index = locales.indexOf(_mainLocale);
    return index != -1
        ? [
            locales.elementAt(index),
            ...locales.sublist(0, index),
            ...locales.sublist(index + 1)
          ]
        : locales;
  }

  Future<void> _generateDartFiles(EncryptionWrapper wrapper) async {
    var outputDir = getIntlDirectoryPath(_outputDir);
    var dartFiles = [getL10nDartFilePath(_outputDir)];
    var arbFiles = getArbFiles(_arbDir).map((file) => file.path).toList();

    var helper = IntlTranslationHelper(_useDeferredLoading);
    await helper.generateFromArb(outputDir, dartFiles, arbFiles, wrapper);
  }
}
