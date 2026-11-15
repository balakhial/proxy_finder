import 'dart:io';

Future<int?> probeProxy(String server, int port) async {
  final samples = <int>[];
  for (var i = 0; i < 3; i++) {
    final watch = Stopwatch()..start();
    try {
      final socket = await Socket.connect(
        server,
        port,
        timeout: const Duration(milliseconds: 1800),
      );
      watch.stop();
      socket.destroy();
      samples.add(watch.elapsedMilliseconds);
    } on Object {
      // Ignore failed attempts; all failed attempts mean unreachable.
    }
  }
  if (samples.isEmpty) return null;
  samples.sort();
  return samples[samples.length ~/ 2];
}
