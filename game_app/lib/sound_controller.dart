import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

class SoundController {
  SoundController() {
    _setupFuture = _setup();
  }

  final AudioPlayer _player = AudioPlayer();
  late final Future<void> _setupFuture;
  bool _enabled = true;

  bool get enabled => _enabled;

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    await _setupFuture;
    if (!value) {
      await _player.stop();
    }
  }

  Future<void> playMove({required bool merged}) async {
    if (!_enabled) {
      return;
    }
    await _playTone(
      frequency: merged ? 520 : 360,
      durationMs: merged ? 120 : 70,
      volume: merged ? 0.22 : 0.12,
    );
  }

  Future<void> playUndo() async {
    if (!_enabled) {
      return;
    }
    await _playSweep(
      startFrequency: 540,
      endFrequency: 380,
      durationMs: 90,
      volume: 0.18,
    );
  }

  Future<void> playRestart() async {
    if (!_enabled) {
      return;
    }
    await _playSweep(
      startFrequency: 320,
      endFrequency: 520,
      durationMs: 110,
      volume: 0.18,
    );
  }

  Future<void> playWin() async {
    if (!_enabled) {
      return;
    }
    await _playChord(
      frequencies: const [523, 659, 784],
      durationMs: 220,
      volume: 0.2,
    );
  }

  Future<void> playLose() async {
    if (!_enabled) {
      return;
    }
    await _playSweep(
      startFrequency: 420,
      endFrequency: 180,
      durationMs: 240,
      volume: 0.2,
    );
  }

  Future<void> dispose() async {
    await _setupFuture;
    await _player.dispose();
  }

  Future<void> _setup() async {
    await _player.setPlayerMode(PlayerMode.lowLatency);
    await _player.setReleaseMode(ReleaseMode.stop);
  }

  Future<void> _playTone({
    required double frequency,
    required int durationMs,
    required double volume,
  }) async {
    await _setupFuture;
    final wav = _buildWavBytes(
      durationMs: durationMs,
      sampleBuilder: (sampleIndex, sampleRate, sampleCount) {
        final t = sampleIndex / sampleRate;
        final fade = _fadeEnvelope(sampleIndex, sampleCount);
        return sin(2 * pi * frequency * t) * fade;
      },
    );

    await _player.stop();
    await _player.setVolume(volume.clamp(0.0, 1.0).toDouble());
    await _player.play(BytesSource(wav, mimeType: 'audio/wav'));
  }

  Future<void> _playSweep({
    required double startFrequency,
    required double endFrequency,
    required int durationMs,
    required double volume,
  }) async {
    await _setupFuture;
    final wav = _buildWavBytes(
      durationMs: durationMs,
      sampleBuilder: (sampleIndex, sampleRate, sampleCount) {
        final progress = sampleCount <= 1
            ? 1.0
            : sampleIndex / (sampleCount - 1);
        final frequency =
            startFrequency + (endFrequency - startFrequency) * progress;
        final t = sampleIndex / sampleRate;
        final fade = _fadeEnvelope(sampleIndex, sampleCount);
        return sin(2 * pi * frequency * t) * fade;
      },
    );

    await _player.stop();
    await _player.setVolume(volume.clamp(0.0, 1.0).toDouble());
    await _player.play(BytesSource(wav, mimeType: 'audio/wav'));
  }

  Future<void> _playChord({
    required List<double> frequencies,
    required int durationMs,
    required double volume,
  }) async {
    await _setupFuture;
    final wav = _buildWavBytes(
      durationMs: durationMs,
      sampleBuilder: (sampleIndex, sampleRate, sampleCount) {
        final t = sampleIndex / sampleRate;
        final fade = _fadeEnvelope(sampleIndex, sampleCount);
        var sum = 0.0;
        for (final frequency in frequencies) {
          sum += sin(2 * pi * frequency * t);
        }
        return (sum / frequencies.length) * fade;
      },
    );

    await _player.stop();
    await _player.setVolume(volume.clamp(0.0, 1.0).toDouble());
    await _player.play(BytesSource(wav, mimeType: 'audio/wav'));
  }

  Uint8List _buildWavBytes({
    required int durationMs,
    required double Function(int sampleIndex, int sampleRate, int sampleCount)
    sampleBuilder,
  }) {
    const sampleRate = 22050;
    const channels = 1;
    const bitsPerSample = 16;
    final sampleCount = max(1, (sampleRate * durationMs / 1000).round());
    final dataSize = sampleCount * channels * (bitsPerSample ~/ 8);
    final byteData = ByteData(44 + dataSize);

    void writeAscii(int offset, String value) {
      for (var index = 0; index < value.length; index++) {
        byteData.setUint8(offset + index, value.codeUnitAt(index));
      }
    }

    writeAscii(0, 'RIFF');
    byteData.setUint32(4, 36 + dataSize, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    byteData.setUint32(16, 16, Endian.little);
    byteData.setUint16(20, 1, Endian.little);
    byteData.setUint16(22, channels, Endian.little);
    byteData.setUint32(24, sampleRate, Endian.little);
    byteData.setUint32(
      28,
      sampleRate * channels * (bitsPerSample ~/ 8),
      Endian.little,
    );
    byteData.setUint16(32, channels * (bitsPerSample ~/ 8), Endian.little);
    byteData.setUint16(34, bitsPerSample, Endian.little);
    writeAscii(36, 'data');
    byteData.setUint32(40, dataSize, Endian.little);

    var byteOffset = 44;
    for (var sampleIndex = 0; sampleIndex < sampleCount; sampleIndex++) {
      final sample = sampleBuilder(
        sampleIndex,
        sampleRate,
        sampleCount,
      ).clamp(-1.0, 1.0);
      byteData.setInt16(byteOffset, (sample * 32767).round(), Endian.little);
      byteOffset += 2;
    }

    return byteData.buffer.asUint8List();
  }

  double _fadeEnvelope(int sampleIndex, int sampleCount) {
    final fadeSamples = max(1, sampleCount ~/ 8);
    final attack = sampleIndex < fadeSamples ? sampleIndex / fadeSamples : 1.0;
    final release = sampleIndex > sampleCount - fadeSamples
        ? (sampleCount - sampleIndex) / fadeSamples
        : 1.0;
    return attack.clamp(0.0, 1.0) * release.clamp(0.0, 1.0);
  }
}
