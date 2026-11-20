import 'dart:io';
import 'dart:typed_data';

/// Pure-Dart FIPS 180-4 SHA-256 hex digest for TLS certificate fingerprint pinning.
String sha256Hex(Uint8List input) {
  const k = <int>[
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];
  var h0 = 0x6a09e667;
  var h1 = 0xbb67ae85;
  var h2 = 0x3c6ef372;
  var h3 = 0xa54ff53a;
  var h4 = 0x510e527f;
  var h5 = 0x9b05688c;
  var h6 = 0x1f83d9ab;
  var h7 = 0x5be0cd19;

  int rotr(int x, int n) => ((x & 0xffffffff) >>> n) | ((x << (32 - n)) & 0xffffffff);

  final bitLen = input.length * 8;
  final padLen = ((56 - (input.length + 1) % 64) + 64) % 64;
  final padded = Uint8List(input.length + 1 + padLen + 8);
  padded.setAll(0, input);
  padded[input.length] = 0x80;
  final bd = ByteData.sublistView(padded);
  bd.setUint64(padded.length - 8, bitLen, Endian.big);

  final w = List<int>.filled(64, 0);
  for (var offset = 0; offset < padded.length; offset += 64) {
    for (var i = 0; i < 16; i++) {
      w[i] = bd.getUint32(offset + i * 4, Endian.big);
    }
    for (var i = 16; i < 64; i++) {
      final s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3);
      final s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
    }
    var a = h0, b = h1, c = h2, d = h3, e = h4, f = h5, g = h6, h = h7;
    for (var i = 0; i < 64; i++) {
      final s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
      final ch = (e & f) ^ ((~e & 0xffffffff) & g);
      final t1 = (h + s1 + ch + k[i] + w[i]) & 0xffffffff;
      final s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final t2 = (s0 + maj) & 0xffffffff;
      h = g;
      g = f;
      f = e;
      e = (d + t1) & 0xffffffff;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & 0xffffffff;
    }
    h0 = (h0 + a) & 0xffffffff;
    h1 = (h1 + b) & 0xffffffff;
    h2 = (h2 + c) & 0xffffffff;
    h3 = (h3 + d) & 0xffffffff;
    h4 = (h4 + e) & 0xffffffff;
    h5 = (h5 + f) & 0xffffffff;
    h6 = (h6 + g) & 0xffffffff;
    h7 = (h7 + h) & 0xffffffff;
  }

  final words = [h0, h1, h2, h3, h4, h5, h6, h7];
  return words.map((v) => (v & 0xffffffff).toRadixString(16).padLeft(8, '0')).join();
}

final RegExp _sha256HexPattern = RegExp(r'^[0-9a-f]{64}$');

bool _constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}

/// Strictly verifies a self-signed certificate against an exact host, optional port,
/// and non-empty 64-hex-character SHA-256 DER fingerprint.
bool verifyPinnedCertificate({
  required Uint8List derBytes,
  required String host,
  required int port,
  required String allowedHost,
  int? allowedPort,
  required String pinnedSha256,
}) {
  if (allowedHost.trim().isEmpty || host != allowedHost.trim()) return false;
  if (allowedPort != null && port != allowedPort) return false;
  final expected = pinnedSha256.trim().toLowerCase();
  if (!_sha256HexPattern.hasMatch(expected)) return false;
  final actual = sha256Hex(derBytes);
  return _constantTimeEquals(actual, expected);
}

class WizardTlsOverrides extends HttpOverrides {
  WizardTlsOverrides({
    required this.allowedHost,
    required this.pinnedSha256,
    this.allowedPort,
  });

  final String allowedHost;
  final String pinnedSha256;
  final int? allowedPort;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback = (X509Certificate cert, String host, int port) {
      return verifyPinnedCertificate(
        derBytes: cert.der,
        host: host,
        port: port,
        allowedHost: allowedHost,
        allowedPort: allowedPort,
        pinnedSha256: pinnedSha256,
      );
    };
    return client;
  }
}
