import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentwallet/core/crypto.dart';

void main() {
  final key = List<int>.generate(32, (i) => i * 7 % 256);
  final otherKey = List<int>.generate(32, (i) => (i * 7 + 1) % 256);

  group('file encryption (AES-256-GCM)', () {
    test('round-trips arbitrary bytes', () async {
      final data = Uint8List.fromList(List.generate(5000, (i) => i % 256));
      final enc = await encryptBytes(data, key);
      expect(await decryptBytes(enc, key), data);
    });

    test('ciphertext does not contain the plaintext', () async {
      final plain = utf8.encode('SECRET RECEIPT 12345 SECRET RECEIPT');
      final enc = await encryptBytes(plain, key);
      expect(String.fromCharCodes(enc).contains('SECRET RECEIPT'), isFalse);
      expect(enc.length, plain.length + 12 + 16); // nonce + mac overhead
    });

    test('same input encrypts differently each time (random nonce)', () async {
      final a = await encryptBytes([1, 2, 3], key);
      final b = await encryptBytes([1, 2, 3], key);
      expect(a, isNot(b));
    });

    test('empty input works', () async {
      expect(await decryptBytes(await encryptBytes([], key), key), isEmpty);
    });

    test('wrong key fails', () async {
      final enc = await encryptBytes([1, 2, 3], key);
      expect(() => decryptBytes(enc, otherKey), throwsA(anything));
    });

    test('tampered ciphertext is detected', () async {
      final enc = await encryptBytes(List.filled(100, 9), key);
      enc[40] ^= 0x01;
      expect(() => decryptBytes(enc, key), throwsA(anything));
    });
  });

  group('password backup container', () {
    final payload = Uint8List.fromList(
      utf8.encode(jsonEncode({'accounts': [], 'note': 'नमस्ते ₹100'})),
    );

    test('round-trips with the right password', () async {
      final enc = await encryptBackup(payload, 'correct horse');
      expect(await decryptBackup(enc, 'correct horse'), payload);
    });

    test('starts with the SWB1 header and hides the content', () async {
      final enc = await encryptBackup(payload, 'pw123456');
      expect(enc.sublist(0, 4), [0x53, 0x57, 0x42, 0x31]);
      expect(String.fromCharCodes(enc).contains('accounts'), isFalse);
    });

    test('wrong password gives a friendly error', () async {
      final enc = await encryptBackup(payload, 'right-password');
      expect(
        () => decryptBackup(enc, 'wrong-password'),
        throwsA(
          isA<BadBackupException>().having(
            (e) => e.message,
            'message',
            contains('Wrong password'),
          ),
        ),
      );
    });

    test('corrupted file is rejected, not crashed on', () async {
      final enc = await encryptBackup(payload, 'right-password');
      enc[enc.length - 5] ^= 0xFF;
      expect(
        () => decryptBackup(enc, 'right-password'),
        throwsA(isA<BadBackupException>()),
      );
    });

    test('non-backup and truncated files are rejected', () async {
      expect(
        () => decryptBackup(utf8.encode('hello world, not a backup'), 'x'),
        throwsA(isA<BadBackupException>()),
      );
      expect(
        () => decryptBackup(<int>[], 'x'),
        throwsA(isA<BadBackupException>()),
      );
      expect(
        () => decryptBackup([0x53, 0x57, 0x42, 0x31, 1, 2, 3], 'x'),
        throwsA(isA<BadBackupException>()),
      );
    });

    test('random salt makes two backups of the same data differ', () async {
      final a = await encryptBackup(payload, 'same-pass');
      final b = await encryptBackup(payload, 'same-pass');
      expect(a, isNot(b));
      expect(await decryptBackup(a, 'same-pass'), payload);
      expect(await decryptBackup(b, 'same-pass'), payload);
    });

    test('handles a large payload (receipt-sized)', () async {
      final r = Random(42);
      final big = Uint8List.fromList(
        List.generate(2 * 1024 * 1024, (_) => r.nextInt(256)),
      );
      final enc = await encryptBackup(big, 'big-file-pass');
      expect(await decryptBackup(enc, 'big-file-pass'), big);
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
