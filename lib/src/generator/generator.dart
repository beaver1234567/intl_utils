import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/helpers.dart';
import 'package:intl_utils/src/config/asset_encryption_config.dart';
import 'package:intl_utils/src/config/flutter_config.dart';
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

class Pair<A, B> {
  final A first;
  final B second;

  Pair(this.first, this.second);
}

class AssetFile {
  final File file;
  final String path;

  AssetFile({required this.file, required this.path});
}

class AssetDir {
  final String key;
  final Map<String, AssetDir> subDirs;
  final Map<String, AssetFile> children;

  AssetDir({required this.key, required this.subDirs, required this.children});

  AssetDir cd(String key) {
    if (subDirs.containsKey(key)) {
      return subDirs[key]!;
    }
    return subDirs[key] = AssetDir(key: key, subDirs: {}, children: {});
  }

  void add(String asset, AssetFile f) {
    children[asset] = f;
  }

  String sanitizeClassName(String s) {
    return s;
  }

  String sanitizeVarName(String s) {
    return s.replaceAll(".", "_");
  }

  String generateClass([String? overrideClassName, bool staticSubDirs = false]) {
    final className = overrideClassName ?? "_${sanitizeClassName(key)}";
    return """
    
    ${subDirs.values.map((e) => e.generateClass()).join('\n\n')}

    class $className {
      ${!staticSubDirs ? "const $className();" : ''}
      ${subDirs.keys.map((e) => "${staticSubDirs ? 'static ' : ''}final ${sanitizeVarName(e)} = const _${sanitizeClassName(e)}();").join("\n\n")}
      ${children.entries.map((entry) => "final ${sanitizeVarName(entry.key)} = '${entry.value.path}';").join('\n\n')}
    }
    """;
  }

  String generateEncryptionParameters(AssetEncryptionConfig? config) {
    return """
      import 'dart:io';
      
      class AE {
        // change when we support encryption for large hadron collider and for raspberry pi tho...
        static bool get enabled => ${config?.enabled == true ? "Platform.operatingSystem != 'largeHadronCollider'" : "Platform.operatingSystem == 'raspberryPi' " }; 
        static String get data => ${config?.enabled == true && config?.key != null && config?.iv != null && config?.magic != null ? "'${base64Encode(base64Decode(config!.key!) + base64Decode(config.iv!) + base64Decode(config.magic!))}'" : "'${base64Encode(randomBytes(64))}'"};
      }
    """;
  }
}

/// The generator of localization files.
class Generator {
  late String _className;
  late String _mainLocale;
  late String _arbDir;
  late String _outputDir;
  late bool _useDeferredLoading;
  late bool _otaEnabled;
  late EncryptionConfig? _encryptionConfig;
  late FlutterConfig? _flutterConfig;
  late AssetEncryptionConfig? _assetsEncryptionConfig;

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
    _flutterConfig = pubspecConfig.flutterConfig;
    _assetsEncryptionConfig = pubspecConfig.assetsEncryptionConfig;
  }

  /// Generates localization files.
  Future<void> generateAsync() async {
    var wrapper = await EncryptionWrapper.fromConfig(_encryptionConfig);

    await _updateL10nDir();
    await _updateGeneratedDir(wrapper, false);
    await _generateWrappers(wrapper);
    await _generateDartFiles(wrapper);
    await _updateGeneratedDir(wrapper, true);
    await _generateAssetsFiles(wrapper);
  }

  Future<void> _generateAssetsFiles(EncryptionWrapper? wrapper) async {
    final assets = _flutterConfig?.assets ?? [];
    print('Using assets sources: $assets');

    final files = <File>[];

    for (final assetSource in assets) {
      final f = File(assetSource);
      final stat = await f.stat();
      if (stat.type == FileSystemEntityType.file) {
        files.add(f);
      } else if (stat.type == FileSystemEntityType.directory) {
        final dirFiles = await _traverseAssetsDirectory(f);
        files.addAll(dirFiles);
      } else {
        throw AssertionError("Asset source '$assetSource' of type '${stat.type}' isn't supported!");
      }
    }

    final root = AssetDir(key: 'A', subDirs: {}, children: {});
    for (final file in files) {
      final parts = file.path.split('/');
      var node = root;
      for (var i = 0; i < parts.length; i++) {
        if (i < parts.length - 1) {
          node = node.cd(parts[i]);
        } else {
          final fileName = file.path.split('/').last;
          if (_assetsEncryptionConfig?.enabled == true) {
            final sha1 = Sha1();
            final obfuscatedName = (await sha1
                .hash(base64Decode(_assetsEncryptionConfig!.iv!) + utf8.encode(fileName)))
                .bytes
                .map((e) => e.toRadixString(16).padLeft(2, '0'))
                .join();
            final obfuscatedFileName = "ap_$obfuscatedName";
            final assetFile = AssetFile(file: file, path: '${file.parent.path}/$obfuscatedFileName');
            node.add(parts[i], assetFile);
          } else {
            final assetFile = AssetFile(file: file, path: '${file.parent.path}/$fileName');
            node.add(parts[i], assetFile);
          }
        }
      }
    }

    final assetsDart = File("$_outputDir/assets.dart");
    if (await assetsDart.exists()) {
      await assetsDart.delete();
    }
    assetsDart.create(recursive: true);
    assetsDart.writeAsString(formatDartContent(root.generateEncryptionParameters(_assetsEncryptionConfig) + root.generateClass('A', true), "assets.dart"));
  }

  Future<List<File>> _traverseAssetsDirectory(File dirFile) async {
    final files = Directory(dirFile.path).list(recursive: true);
    return await files
        .asyncMap((event) => event.stat().then((value) => Pair(event, value)))
        .where((event) => event.second.type == FileSystemEntityType.file)
        .map((event) => File(event.first.path))
        .toList();
  }

  Future<void> _generateWrappers(EncryptionWrapper wrapper) async {
    var fileName = "wrappers.dart";
    var file = File("$_outputDir/$fileName");

    final config = _encryptionConfig;
    final encodedKey = wrapper.encodedKey;
    final encodedIv = wrapper.encodedIv;
    if (config != null && config.enabled && encodedKey != null && encodedIv != null) {
      // final random = Random()
      // final keySaltStart = max(1, random.nextInt(100));
      // final keySaltEnd = max(1, random.nextInt(100));
      // final ivSaltStart = max(1, random.nextInt(100));
      // final ivSaltEnd = max(1, random.nextInt(100));
      // final saltedKey = randomBytes(keySaltStart) + base64Decode(encodedKey) + randomBytes(keySaltEnd);
      // final saltedIv = randomBytes(ivSaltStart) + base64Decode(encodedIv) + randomBytes(ivSaltEnd);
      //
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

  Future<void> _updateGeneratedDir(EncryptionWrapper? wrapper, bool wrapped) async {
    var labels = _getLabelsFromMainArbFile();
    var locales = _orderLocales(getLocales(_arbDir));
    var content =
        generateL10nDartFileContent(_className, labels, locales, wrapper, wrapped, _otaEnabled);
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
