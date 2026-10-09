import 'dart:convert';

import 'package:limenia/src/sha256.dart';
import 'package:test/test.dart';

String hex(List<int> bytes) => [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();

void main() {
  // The examples of FIPS 180-2 (appendix B) and the NIST test vectors.
  test('NIST vectors', () {
    expect(hex(sha256(const [])), 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
    expect(hex(sha256(ascii.encode('abc'))), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    expect(
      hex(sha256(ascii.encode('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq'))),
      '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
    );
    expect(
      hex(sha256(ascii.encode('abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmn'
          'hijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu'))),
      'cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1',
    );
    expect(
      hex(sha256(List.filled(1000000, 0x61))),
      'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0',
    );
  });

  // Lengths around the block size (64 bytes), where the padding takes one
  // block more or less. Expected values from Python's hashlib.
  test('lengths around the padding boundaries', () {
    const expected = {
      55: '463eb28e72f82e0a96c0a4cc53690c571281131f672aa229e0d45ae59b598b59',
      56: 'da2ae4d6b36748f2a318f23e7ab1dfdf45acdc9d049bd80e59de82a60895f562',
      63: '29af2686fd53374a36b0846694cc342177e428d1647515f078784d69cdb9e488',
      64: 'fdeab9acf3710362bd2658cdc9a29e8f9c757fcf9811603a8c447cd1d9151108',
      65: '4bfd2c8b6f1eec7a2afeb48b934ee4b2694182027e6d0fc075074f2fabb31781',
      119: 'da18797ed7c3a777f0847f429724a2d8cd5138e6ed2895c3fa1a6d39d18f7ec6',
      120: 'f52b23db1fbb6ded89ef42a23ce0c8922c45f25c50b568a93bf1c075420bbb7c',
      127: '92ca0fa6651ee2f97b884b7246a562fa71250fedefe5ebf270d31c546bfea976',
      128: '471fb943aa23c511f6f72f8d1652d9c880cfa392ad80503120547703e56a2be5',
    };
    for (final MapEntry(key: length, value: digest) in expected.entries) {
      expect(hex(sha256([for (var i = 0; i < length; i++) i])), digest, reason: '$length bytes');
    }
    expect(
      hex(sha256([for (var r = 0; r < 4; r++) ...List.generate(256, (i) => i)])),
      '785b0751fc2c53dc14a4ce3d800e69ef9ce1009eb327ccf458afe09c242c26c9',
    );
  });

  test('the digest has 32 bytes and the input is not changed', () {
    final input = [1, 2, 3];
    expect(sha256(input), hasLength(32));
    expect(input, [1, 2, 3]);
  });
}
