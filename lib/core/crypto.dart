import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keys live in the Android Keystore (via flutter_secure_storage) and never
/// leave the device. resetOnError is disabled so a transient keystore error
/// can never silently wipe the key (which would make the data unreadable).
class KeyStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: false),
  );

  static Future<String> _getOrCreate(String name) async {
    var v = await _storage.read(key: name);
    if (v == null) {
      final r = Random.secure();
      v = base64Url.encode(List<int>.generate(32, (_) => r.nextInt(256)));
      await _storage.write(key: name, value: v);
    }
    return v;
  }

  static Future<String> dbKey() => _getOrCreate('sw_db_key');
  static Future<List<int>> fileKey() async =>
      base64Url.decode(await _getOrCreate('sw_file_key'));
}

final _aes = AesGcm.with256bits();

/// Encrypts bytes: output = nonce(12) | ciphertext | mac(16)
Future<Uint8List> encryptBytes(List<int> plain, List<int> key) async {
  final box = await _aes.encrypt(plain, secretKey: SecretKey(key));
  return box.concatenation();
}

Future<Uint8List> decryptBytes(List<int> data, List<int> key) async {
  final box = SecretBox.fromConcatenation(
    data,
    nonceLength: 12,
    macLength: 16,
  );
  return Uint8List.fromList(await _aes.decrypt(box, secretKey: SecretKey(key)));
}

// ---- Password-protected backup container ----
// "SWB1" | salt(16) | nonce(12) | ciphertext | mac(16)
const _magic = [0x53, 0x57, 0x42, 0x31];
const _iterations = 120000;

Future<SecretKey> _deriveKey(String password, List<int> salt) {
  final kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: _iterations,
    bits: 256,
  );
  return kdf.deriveKeyFromPassword(password: password, nonce: salt);
}

Future<Uint8List> encryptBackup(List<int> plain, String password) async {
  final r = Random.secure();
  final salt = List<int>.generate(16, (_) => r.nextInt(256));
  final key = await _deriveKey(password, salt);
  final box = await _aes.encrypt(plain, secretKey: key);
  return Uint8List.fromList([..._magic, ...salt, ...box.concatenation()]);
}

class BadBackupException implements Exception {
  final String message;
  BadBackupException(this.message);
  @override
  String toString() => message;
}

Future<Uint8List> decryptBackup(List<int> data, String password) async {
  if (data.length < 4 + 16 + 12 + 16 ||
      !List.generate(4, (i) => data[i] == _magic[i]).every((e) => e)) {
    throw BadBackupException('This is not a Silent Wallet backup file.');
  }
  final salt = data.sublist(4, 20);
  final key = await _deriveKey(password, salt);
  try {
    final box = SecretBox.fromConcatenation(
      data.sublist(20),
      nonceLength: 12,
      macLength: 16,
    );
    return Uint8List.fromList(await _aes.decrypt(box, secretKey: key));
  } on SecretBoxAuthenticationError {
    throw BadBackupException('Wrong password, or the file is damaged.');
  }
}
