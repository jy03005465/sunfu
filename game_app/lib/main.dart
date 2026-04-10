import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'game_logic.dart';
import 'sound_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  runApp(MyApp(preferences: preferences));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.preferences});

  final SharedPreferences preferences;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '2048 Solo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFF59E0B),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0B1220),
      ),
      home: GamePage(preferences: preferences),
    );
  }
}

enum _TileAnimationKind { spawn, merge }

class _TileAnimationData {
  const _TileAnimationData({required this.kind, required this.tick});

  final _TileAnimationKind kind;
  final int tick;
}

class _GameBrand {
  static const appName = '2048 Solo';
  static const tagline = '离线也能玩的数字合成小游戏';
  static const version = 'Build 1.2';
}

class GamePage extends StatefulWidget {
  const GamePage({super.key, required this.preferences});

  final SharedPreferences preferences;

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  static const _bestScoreKey = 'best_score';
  static const _savedGameKey = 'saved_game_v2';
  static const _soundEnabledKey = 'sound_enabled';
  static const _hapticsEnabledKey = 'haptics_enabled';
  static const _onboardingSeenKey = 'onboarding_seen_v1';

  late final TileGame _game;
  late final SoundController _soundController;
  late int _bestScore;
  late bool _soundEnabled;
  late bool _hapticsEnabled;

  bool _wonShown = false;
  int _moveCount = 0;
  int _lastMoveGain = 0;
  int _animationTick = 0;

  BoardSnapshot? _lastSnapshot;
  Map<int, _TileAnimationData> _tileAnimations = const {};

  @override
  void initState() {
    super.initState();
    _bestScore = widget.preferences.getInt(_bestScoreKey) ?? 0;
    _soundEnabled = widget.preferences.getBool(_soundEnabledKey) ?? true;
    _hapticsEnabled = widget.preferences.getBool(_hapticsEnabledKey) ?? true;
    _soundController = SoundController();
    unawaited(_soundController.setEnabled(_soundEnabled));
    _game = _loadGame();
    _tileAnimations = _buildInitialAnimations();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowOnboarding());
  }

  @override
  void dispose() {
    unawaited(_soundController.dispose());
    super.dispose();
  }

  TileGame _loadGame() {
    final encoded = widget.preferences.getString(_savedGameKey);
    if (encoded == null) {
      return TileGame();
    }

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic>) {
        return TileGame();
      }

      final game = TileGame.fromJson(decoded);
      _moveCount = game.moveCount;
      _wonShown = game.hasWon;
      return game;
    } catch (_) {
      return TileGame();
    }
  }

  Map<int, _TileAnimationData> _buildInitialAnimations() {
    final animations = <int, _TileAnimationData>{};
    for (var row = 0; row < _game.size; row++) {
      for (var column = 0; column < _game.size; column++) {
        final value = _game.board[row][column];
        if (value != 0) {
          final index = row * _game.size + column;
          animations[index] = _nextTileAnimation(_TileAnimationKind.spawn);
        }
      }
    }
    return animations;
  }

  Map<int, _TileAnimationData> _buildTileAnimations(
    BoardSnapshot previous,
    BoardSnapshot current,
  ) {
    final animations = <int, _TileAnimationData>{};
    for (var row = 0; row < _game.size; row++) {
      for (var column = 0; column < _game.size; column++) {
        final before = previous.board[row][column];
        final after = current.board[row][column];
        if (after == 0 || before == after) {
          continue;
        }

        final kind = before == 0 || after <= before
            ? _TileAnimationKind.spawn
            : _TileAnimationKind.merge;
        final index = row * _game.size + column;
        animations[index] = _nextTileAnimation(kind);
      }
    }
    return animations;
  }

  _TileAnimationData _nextTileAnimation(_TileAnimationKind kind) {
    _animationTick += 1;
    return _TileAnimationData(kind: kind, tick: _animationTick);
  }

  Future<void> _persistGame() async {
    await widget.preferences.setString(
      _savedGameKey,
      jsonEncode(_game.toJson()),
    );
  }

  Future<void> _persistBestScore() {
    return widget.preferences.setInt(_bestScoreKey, _bestScore);
  }

  Future<void> _persistSoundSetting() {
    return widget.preferences.setBool(_soundEnabledKey, _soundEnabled);
  }

  Future<void> _persistHapticsSetting() {
    return widget.preferences.setBool(_hapticsEnabledKey, _hapticsEnabled);
  }

  Future<void> _maybeHaptic(Future<void> Function() callback) async {
    if (_hapticsEnabled) {
      await callback();
    }
  }

  Future<void> _toggleSound() async {
    await _maybeHaptic(HapticFeedback.selectionClick);
    final nextEnabled = !_soundEnabled;
    setState(() {
      _soundEnabled = nextEnabled;
    });
    await _soundController.setEnabled(nextEnabled);
    await _persistSoundSetting();
    if (mounted) {
      _showToast(nextEnabled ? '音效已开启' : '音效已关闭');
    }
  }

  Future<void> _restart() async {
    await _maybeHaptic(HapticFeedback.mediumImpact);
    _game.reset();
    setState(() {
      _wonShown = false;
      _moveCount = 0;
      _lastMoveGain = 0;
      _lastSnapshot = null;
      _tileAnimations = _buildInitialAnimations();
    });
    await _persistGame();
    unawaited(_soundController.playRestart());
  }

  Future<void> _undoMove() async {
    final snapshot = _lastSnapshot;
    if (snapshot == null) {
      _showToast('当前没有可撤销的步骤');
      return;
    }

    final beforeUndo = _game.snapshot();
    await _maybeHaptic(HapticFeedback.selectionClick);
    _game.restore(snapshot: snapshot);
    setState(() {
      _moveCount = _game.moveCount;
      _lastMoveGain = 0;
      _wonShown = _game.hasWon;
      _lastSnapshot = null;
      _tileAnimations = _buildTileAnimations(beforeUndo, _game.snapshot());
    });
    await _persistGame();
    unawaited(_soundController.playUndo());
  }

  Future<void> _handleMove(MoveDirection direction) async {
    final previousSnapshot = _game.snapshot();
    final result = _game.move(direction);
    if (!result.changed) {
      await _maybeHaptic(HapticFeedback.selectionClick);
      return;
    }

    final currentSnapshot = _game.snapshot();
    _lastSnapshot = previousSnapshot;
    _moveCount = _game.moveCount;
    _lastMoveGain = result.gainedScore;

    if (_game.score > _bestScore) {
      _bestScore = _game.score;
      await _persistBestScore();
    }

    await _persistGame();

    if (!mounted) {
      return;
    }

    await _maybeHaptic(HapticFeedback.lightImpact);
    setState(() {
      _tileAnimations = _buildTileAnimations(previousSnapshot, currentSnapshot);
    });

    if (_game.hasWon && !_wonShown) {
      _wonShown = true;
      unawaited(_soundController.playWin());
      await _showGameDialog(
        title: '你赢了！',
        message: '已经合成到 2048，是否继续冲击更高分？',
        primaryLabel: '继续挑战',
        onPrimary: () => Navigator.of(context).pop(),
        secondaryLabel: '重新开始',
        onSecondary: () {
          Navigator.of(context).pop();
          _restart();
        },
      );
      return;
    }

    if (_game.isGameOver) {
      await _maybeHaptic(HapticFeedback.heavyImpact);
      unawaited(_soundController.playLose());
      await _showGameDialog(
        title: '游戏结束',
        message: '当前棋盘已无可移动空间，是否马上再来一局？',
        primaryLabel: '重新开始',
        onPrimary: () {
          Navigator.of(context).pop();
          _restart();
        },
      );
      return;
    }

    unawaited(_soundController.playMove(merged: result.gainedScore > 0));
  }

  Future<void> _maybeShowOnboarding() async {
    final hasSeen = widget.preferences.getBool(_onboardingSeenKey) ?? false;
    if (hasSeen || !mounted) {
      return;
    }

    await widget.preferences.setBool(_onboardingSeenKey, true);
    if (!mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _OnboardingSheet(),
    );
  }

  Future<void> _openSettings() async {
    await _maybeHaptic(HapticFeedback.selectionClick);
    if (!mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, bottomSetState) {
            Future<void> updateSound(bool value) async {
              bottomSetState(() => _soundEnabled = value);
              setState(() => _soundEnabled = value);
              await _soundController.setEnabled(value);
              await _persistSoundSetting();
            }

            Future<void> updateHaptics(bool value) async {
              bottomSetState(() => _hapticsEnabled = value);
              setState(() => _hapticsEnabled = value);
              await _persistHapticsSetting();
            }

            Future<void> resetProgress() async {
              final navigator = Navigator.of(context);
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (dialogContext) {
                  return AlertDialog(
                    backgroundColor: const Color(0xFF172033),
                    title: const Text(
                      '清除本地进度',
                      style: TextStyle(color: Colors.white),
                    ),
                    content: const Text(
                      '这会清空当前棋盘、最高分和首次引导记录，且无法撤回。',
                      style: TextStyle(color: Colors.white70, height: 1.5),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                        child: const Text('确认清除'),
                      ),
                    ],
                  );
                },
              );

              if (confirmed != true) {
                return;
              }

              await widget.preferences.remove(_savedGameKey);
              await widget.preferences.remove(_bestScoreKey);
              await widget.preferences.remove(_onboardingSeenKey);
              _bestScore = 0;
              await _restart();
              if (mounted) {
                navigator.pop();
                _showToast('本地进度已清除');
              }
            }

            Future<void> replayGuide() async {
              Navigator.of(context).pop();
              await widget.preferences.remove(_onboardingSeenKey);
              if (mounted) {
                await _maybeShowOnboarding();
              }
            }

            return _SettingsSheet(
              soundEnabled: _soundEnabled,
              hapticsEnabled: _hapticsEnabled,
              onSoundChanged: updateSound,
              onHapticsChanged: updateHaptics,
              onReplayGuide: replayGuide,
              onResetProgress: resetProgress,
            );
          },
        );
      },
    );
  }

  void _showToast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  Future<void> _showGameDialog({
    required String title,
    required String message,
    required String primaryLabel,
    required VoidCallback onPrimary,
    String? secondaryLabel,
    VoidCallback? onSecondary,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF172033),
          title: Text(title, style: const TextStyle(color: Colors.white)),
          content: Text(
            message,
            style: const TextStyle(color: Colors.white70, height: 1.5),
          ),
          actions: [
            if (secondaryLabel != null && onSecondary != null)
              TextButton(onPressed: onSecondary, child: Text(secondaryLabel)),
            FilledButton(onPressed: onPrimary, child: Text(primaryLabel)),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusLabel = _game.highestTile >= 2048 ? '已突破 2048' : '目标 2048';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity.abs() < 80) {
          return;
        }
        _handleMove(velocity < 0 ? MoveDirection.up : MoveDirection.down);
      },
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity.abs() < 80) {
          return;
        }
        _handleMove(velocity < 0 ? MoveDirection.left : MoveDirection.right);
      },
      child: Scaffold(
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF101827), Color(0xFF0B1220), Color(0xFF060A14)],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Expanded(child: _TitlePanel()),
                          const SizedBox(width: 12),
                          Column(
                            children: [
                              _MiniActionButton(
                                icon: Icons.settings_rounded,
                                label: '设置',
                                onPressed: _openSettings,
                              ),
                              const SizedBox(height: 10),
                              _MiniActionButton(
                                icon: _soundEnabled
                                    ? Icons.volume_up_rounded
                                    : Icons.volume_off_rounded,
                                label: _soundEnabled ? '声音开' : '声音关',
                                highlighted: _soundEnabled,
                                onPressed: _toggleSound,
                              ),
                              const SizedBox(height: 10),
                              _MiniActionButton(
                                icon: Icons.undo_rounded,
                                label: '撤销',
                                highlighted: _lastSnapshot != null,
                                onPressed: _undoMove,
                              ),
                              const SizedBox(height: 10),
                              _MiniActionButton(
                                icon: Icons.refresh_rounded,
                                label: '重开',
                                onPressed: _restart,
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _ScoreCard(
                            label: '当前分数',
                            value: _game.score,
                            accent: const Color(0xFFF59E0B),
                          ),
                          _ScoreCard(
                            label: '最高分',
                            value: _bestScore,
                            accent: const Color(0xFF38BDF8),
                          ),
                          _ScoreCard(
                            label: '最大方块',
                            value: _game.highestTile,
                            accent: const Color(0xFF34D399),
                          ),
                          _ScoreCard(
                            label: '步数',
                            value: _moveCount,
                            accent: const Color(0xFFFB7185),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _InfoBanner(
                        lastMoveGain: _lastMoveGain,
                        statusLabel: statusLabel,
                        canUndo: _lastSnapshot != null,
                        soundEnabled: _soundEnabled,
                        hapticsEnabled: _hapticsEnabled,
                      ),
                      const SizedBox(height: 18),
                      Expanded(
                        child: Center(
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A2438),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.05),
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x55000000),
                                    blurRadius: 24,
                                    offset: Offset(0, 16),
                                  ),
                                ],
                              ),
                              child: GridView.builder(
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _game.size * _game.size,
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: _game.size,
                                      mainAxisSpacing: 10,
                                      crossAxisSpacing: 10,
                                    ),
                                itemBuilder: (context, index) {
                                  final row = index ~/ _game.size;
                                  final column = index % _game.size;
                                  final value = _game.board[row][column];
                                  return _TileCell(
                                    key: ValueKey(index),
                                    value: value,
                                    animation: _tileAnimations[index],
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      _ControlPad(onMove: _handleMove),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TitlePanel extends StatelessWidget {
  const _TitlePanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF131D31),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _BrandBadge(),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _GameBrand.appName,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      _GameBrand.version,
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          Text(
            '离线也能玩的数字合成小游戏。滑动屏幕，合并相同数字，冲击更高分。',
            style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _BrandBadge extends StatelessWidget {
  const _BrandBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFBBF24), Color(0xFF8B5CF6)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x44F59E0B),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: const Center(
        child: Text(
          '24',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 22,
          ),
        ),
      ),
    );
  }
}

class _MiniActionButton extends StatelessWidget {
  const _MiniActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 84,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: highlighted
              ? const Color(0xFFF59E0B)
              : const Color(0xFF1A2438),
          foregroundColor: highlighted ? const Color(0xFF111827) : Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
          ),
        ),
        onPressed: onPressed,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final int value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 120),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF131D31),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 6),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(scale: animation, child: child),
              );
            },
            child: Text(
              '$value',
              key: ValueKey(value),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.lastMoveGain,
    required this.statusLabel,
    required this.canUndo,
    required this.soundEnabled,
    required this.hapticsEnabled,
  });

  final int lastMoveGain;
  final String statusLabel;
  final bool canUndo;
  final bool soundEnabled;
  final bool hapticsEnabled;

  @override
  Widget build(BuildContext context) {
    final gainText = lastMoveGain > 0 ? '+$lastMoveGain' : '保持节奏';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF131D31),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: _BannerStat(title: '状态', value: statusLabel),
          ),
          Expanded(
            child: _BannerStat(title: '本次得分', value: gainText),
          ),
          Expanded(
            child: _BannerStat(title: '撤销', value: canUndo ? '可用' : '未准备'),
          ),
          Expanded(
            child: _BannerStat(title: '音效', value: soundEnabled ? '开启' : '关闭'),
          ),
          Expanded(
            child: _BannerStat(
              title: '震动',
              value: hapticsEnabled ? '开启' : '关闭',
            ),
          ),
        ],
      ),
    );
  }
}

class _BannerStat extends StatelessWidget {
  const _BannerStat({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 4),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.15),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            );
          },
          child: Text(
            value,
            key: ValueKey(value),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _TileCell extends StatefulWidget {
  const _TileCell({super.key, required this.value, this.animation});

  final int value;
  final _TileAnimationData? animation;

  @override
  State<_TileCell> createState() => _TileCellState();
}

class _TileCellState extends State<_TileCell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _configureAnimation();
    if (widget.animation != null && widget.value != 0) {
      _controller.forward(from: 0);
    } else {
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant _TileCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changedAnimation =
        widget.animation?.tick != oldWidget.animation?.tick;
    final changedValue = widget.value != oldWidget.value;
    if (changedAnimation || changedValue) {
      _configureAnimation();
      if (widget.animation != null && widget.value != 0) {
        _controller.forward(from: 0);
      } else {
        _controller.value = 1;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _configureAnimation() {
    final beginScale = switch (widget.animation?.kind) {
      _TileAnimationKind.merge => 1.18,
      _TileAnimationKind.spawn => 0.72,
      null => 1.0,
    };

    _scaleAnimation = Tween<double>(
      begin: beginScale,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final glowBoost = widget.animation?.kind == _TileAnimationKind.merge
            ? (1 - _controller.value) * 0.38
            : (1 - _controller.value) * 0.18;

        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _tileGradient(widget.value),
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: widget.value == 0
                  ? null
                  : [
                      BoxShadow(
                        color: _tileGradient(
                          widget.value,
                        ).last.withValues(alpha: 0.22 + glowBoost),
                        blurRadius: 12 + 14 * glowBoost,
                        offset: const Offset(0, 8),
                      ),
                    ],
            ),
            alignment: Alignment.center,
            child: child,
          ),
        );
      },
      child: widget.value == 0
          ? null
          : FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Text(
                  '${widget.value}',
                  style: TextStyle(
                    color: widget.value <= 4
                        ? const Color(0xFF111827)
                        : Colors.white,
                    fontSize: widget.value >= 1024 ? 28 : 34,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
    );
  }

  List<Color> _tileGradient(int value) {
    switch (value) {
      case 0:
        return const [Color(0xFF2B3447), Color(0xFF253044)];
      case 2:
        return const [Color(0xFFFEF3C7), Color(0xFFFDE68A)];
      case 4:
        return const [Color(0xFFFDE68A), Color(0xFFFCD34D)];
      case 8:
        return const [Color(0xFFFBBF24), Color(0xFFF59E0B)];
      case 16:
        return const [Color(0xFFFDA65D), Color(0xFFFB923C)];
      case 32:
        return const [Color(0xFFFB923C), Color(0xFFF97316)];
      case 64:
        return const [Color(0xFFF87171), Color(0xFFEF4444)];
      case 128:
        return const [Color(0xFF4ADE80), Color(0xFF22C55E)];
      case 256:
        return const [Color(0xFF2DD4BF), Color(0xFF14B8A6)];
      case 512:
        return const [Color(0xFF22D3EE), Color(0xFF06B6D4)];
      case 1024:
        return const [Color(0xFF60A5FA), Color(0xFF3B82F6)];
      default:
        return const [Color(0xFFA78BFA), Color(0xFF8B5CF6)];
    }
  }
}

class _ControlPad extends StatelessWidget {
  const _ControlPad({required this.onMove});

  final Future<void> Function(MoveDirection direction) onMove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: const Color(0xFF131D31),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: [
          const Text(
            '方向控制',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          _ArrowButton(
            icon: Icons.keyboard_arrow_up,
            onPressed: () => onMove(MoveDirection.up),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ArrowButton(
                icon: Icons.keyboard_arrow_left,
                onPressed: () => onMove(MoveDirection.left),
              ),
              const SizedBox(width: 54),
              _ArrowButton(
                icon: Icons.keyboard_arrow_right,
                onPressed: () => onMove(MoveDirection.right),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _ArrowButton(
            icon: Icons.keyboard_arrow_down,
            onPressed: () => onMove(MoveDirection.down),
          ),
        ],
      ),
    );
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFFF59E0B),
        foregroundColor: const Color(0xFF111827),
        minimumSize: const Size(72, 58),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      onPressed: onPressed,
      child: Icon(icon, size: 34),
    );
  }
}

class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet({
    required this.soundEnabled,
    required this.hapticsEnabled,
    required this.onSoundChanged,
    required this.onHapticsChanged,
    required this.onReplayGuide,
    required this.onResetProgress,
  });

  final bool soundEnabled;
  final bool hapticsEnabled;
  final Future<void> Function(bool value) onSoundChanged;
  final Future<void> Function(bool value) onHapticsChanged;
  final Future<void> Function() onReplayGuide;
  final Future<void> Function() onResetProgress;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF101827),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        24 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            '设置',
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '调整你的游玩体验，或管理本地数据。',
            style: TextStyle(color: Colors.white70, height: 1.5),
          ),
          const SizedBox(height: 20),
          _SettingsSwitchTile(
            title: '音效反馈',
            subtitle: '控制移动、合并、胜利与失败提示音',
            value: soundEnabled,
            onChanged: (value) => unawaited(onSoundChanged(value)),
          ),
          const SizedBox(height: 12),
          _SettingsSwitchTile(
            title: '触感反馈',
            subtitle: '控制滑动、撤销与结算时的震动反馈',
            value: hapticsEnabled,
            onChanged: (value) => unawaited(onHapticsChanged(value)),
          ),
          const SizedBox(height: 18),
          _SettingsActionTile(
            icon: Icons.auto_awesome_rounded,
            title: '重新查看新手引导',
            subtitle: '再次查看玩法说明与操作提示',
            onTap: () => unawaited(onReplayGuide()),
          ),
          const SizedBox(height: 10),
          _SettingsActionTile(
            icon: Icons.delete_outline_rounded,
            title: '清除本地进度',
            subtitle: '删除当前棋盘、最高分与引导记录',
            destructive: true,
            onTap: () => unawaited(onResetProgress()),
          ),
        ],
      ),
    );
  }
}

class _SettingsSwitchTile extends StatelessWidget {
  const _SettingsSwitchTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF131D31),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white70, height: 1.45),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch.adaptive(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _SettingsActionTile extends StatelessWidget {
  const _SettingsActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final accent = destructive
        ? const Color(0xFFFB7185)
        : const Color(0xFFF59E0B);

    return Material(
      color: const Color(0xFF131D31),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white70,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingSheet extends StatelessWidget {
  const _OnboardingSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF101827),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        24 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Row(
            children: [
              _BrandBadge(),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _GameBrand.appName,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      _GameBrand.tagline,
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const _GuideItem(
            step: '01',
            title: '滑动屏幕或点按方向键',
            description: '每次移动都会让棋盘上的数字向一个方向靠拢。',
          ),
          const SizedBox(height: 12),
          const _GuideItem(
            step: '02',
            title: '相同数字会自动合并',
            description: '例如 2+2=4、4+4=8，持续叠加冲击更高分。',
          ),
          const SizedBox(height: 12),
          const _GuideItem(
            step: '03',
            title: '把 2048 合成出来',
            description: '如果棋盘无路可走则结束，你也可以在设置里重置进度。',
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFF59E0B),
                foregroundColor: const Color(0xFF111827),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                '开始游戏',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideItem extends StatelessWidget {
  const _GuideItem({
    required this.step,
    required this.title,
    required this.description,
  });

  final String step;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF131D31),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                step,
                style: const TextStyle(
                  color: Color(0xFFF59E0B),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: const TextStyle(color: Colors.white70, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
