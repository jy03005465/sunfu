import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'game_logic.dart';

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

class GamePage extends StatefulWidget {
  const GamePage({super.key, required this.preferences});

  final SharedPreferences preferences;

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  static const _bestScoreKey = 'best_score';
  static const _savedGameKey = 'saved_game_v2';

  late final TileGame _game;
  late int _bestScore;
  bool _wonShown = false;
  int _moveCount = 0;
  int _lastMoveGain = 0;
  BoardSnapshot? _lastSnapshot;

  @override
  void initState() {
    super.initState();
    _bestScore = widget.preferences.getInt(_bestScoreKey) ?? 0;
    _game = _loadGame();
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

  Future<void> _persistGame() async {
    await widget.preferences.setString(
      _savedGameKey,
      jsonEncode(_game.toJson()),
    );
  }

  Future<void> _persistBestScore() {
    return widget.preferences.setInt(_bestScoreKey, _bestScore);
  }

  Future<void> _restart() async {
    HapticFeedback.mediumImpact();
    setState(() {
      _wonShown = false;
      _moveCount = 0;
      _lastMoveGain = 0;
      _lastSnapshot = null;
      _game.reset();
    });
    await _persistGame();
  }

  Future<void> _undoMove() async {
    final snapshot = _lastSnapshot;
    if (snapshot == null) {
      _showToast('当前没有可撤销的步骤');
      return;
    }

    HapticFeedback.selectionClick();
    setState(() {
      _game.restore(snapshot: snapshot);
      _moveCount = _game.moveCount;
      _lastMoveGain = 0;
      _wonShown = _game.hasWon;
      _lastSnapshot = null;
    });
    await _persistGame();
  }

  Future<void> _handleMove(MoveDirection direction) async {
    final snapshot = _game.snapshot();
    final result = _game.move(direction);
    if (!result.changed) {
      return;
    }

    _lastSnapshot = snapshot;
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

    HapticFeedback.lightImpact();
    setState(() {});

    if (_game.hasWon && !_wonShown) {
      _wonShown = true;
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
    } else if (_game.isGameOver) {
      HapticFeedback.heavyImpact();
      await _showGameDialog(
        title: '游戏结束',
        message: '当前棋盘已无可移动空间，是否马上再来一局？',
        primaryLabel: '重新开始',
        onPrimary: () {
          Navigator.of(context).pop();
          _restart();
        },
      );
    }
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
    final statusLabel = _game.highestTile >= 2048
        ? '已突破 2048'
        : '目标 ${2048.toString()}';

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
                                icon: Icons.undo_rounded,
                                label: '撤销',
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
                                  return _TileCell(value: value);
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
          Text(
            '2048 Solo',
            style: TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '离线也能玩的数字合成小游戏。滑动屏幕，合并相同数字，冲击更高分。',
            style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _MiniActionButton extends StatelessWidget {
  const _MiniActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 84,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF1A2438),
          foregroundColor: Colors.white,
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
          Text(
            '$value',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
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
  });

  final int lastMoveGain;
  final String statusLabel;
  final bool canUndo;

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
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _TileCell extends StatelessWidget {
  const _TileCell({required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutBack,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _tileGradient(value),
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: value == 0
            ? null
            : [
                BoxShadow(
                  color: _tileGradient(value).last.withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      alignment: Alignment.center,
      child: value == 0
          ? null
          : FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Text(
                  '$value',
                  style: TextStyle(
                    color: value <= 4 ? const Color(0xFF111827) : Colors.white,
                    fontSize: value >= 1024 ? 28 : 34,
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
