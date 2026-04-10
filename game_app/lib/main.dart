import 'package:flutter/material.dart';
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
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFF59E0B)),
        scaffoldBackgroundColor: const Color(0xFF111827),
        fontFamily: 'sans-serif',
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

  late final TileGame _game;
  late int _bestScore;
  var _wonShown = false;

  @override
  void initState() {
    super.initState();
    _game = TileGame();
    _bestScore = widget.preferences.getInt(_bestScoreKey) ?? 0;
  }

  void _restart() {
    setState(() {
      _wonShown = false;
      _game.reset();
    });
  }

  Future<void> _handleMove(MoveDirection direction) async {
    final changed = _game.move(direction);
    if (!changed) {
      return;
    }

    if (_game.score > _bestScore) {
      _bestScore = _game.score;
      await widget.preferences.setInt(_bestScoreKey, _bestScore);
    }

    if (!mounted) {
      return;
    }

    setState(() {});

    if (_game.hasWon && !_wonShown) {
      _wonShown = true;
      await _showGameDialog(
        title: '你赢了！',
        message: '已经合成到 2048，是否继续挑战更高分？',
        primaryLabel: '继续',
        onPrimary: () => Navigator.of(context).pop(),
        secondaryLabel: '重开',
        onSecondary: () {
          Navigator.of(context).pop();
          _restart();
        },
      );
    } else if (_game.isGameOver) {
      await _showGameDialog(
        title: '游戏结束',
        message: '当前没有可移动的方块了，重新来一局？',
        primaryLabel: '重新开始',
        onPrimary: () {
          Navigator.of(context).pop();
          _restart();
        },
      );
    }
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
          backgroundColor: const Color(0xFF1F2937),
          title: Text(title, style: const TextStyle(color: Colors.white)),
          content: Text(message, style: const TextStyle(color: Colors.white70)),
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
        appBar: AppBar(
          title: const Text('2048 Solo'),
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            IconButton(
              onPressed: _restart,
              tooltip: '重新开始',
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      alignment: WrapAlignment.spaceBetween,
                      children: [
                        _ScoreCard(label: '当前分数', value: _game.score),
                        _ScoreCard(label: '最高分', value: _bestScore),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '滑动屏幕移动方块，相同数字会合并。合成 2048 即算胜利。',
                      style: TextStyle(color: Colors.white70, fontSize: 15),
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF374151),
                            borderRadius: BorderRadius.circular(20),
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
                    const SizedBox(height: 20),
                    _ControlPad(onMove: _handleMove),
                    const SizedBox(height: 12),
                    const Text(
                      '如果手势不方便，也可以点击下方方向按钮。',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
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

class _TileCell extends StatelessWidget {
  const _TileCell({required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      decoration: BoxDecoration(
        color: _tileColor(value),
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.center,
      child: value == 0
          ? null
          : Text(
              '$value',
              style: TextStyle(
                color: value <= 4 ? const Color(0xFF111827) : Colors.white,
                fontSize: value >= 1024 ? 26 : 30,
                fontWeight: FontWeight.w800,
              ),
            ),
    );
  }

  Color _tileColor(int value) {
    switch (value) {
      case 0:
        return const Color(0xFF4B5563);
      case 2:
        return const Color(0xFFFDE68A);
      case 4:
        return const Color(0xFFFCD34D);
      case 8:
        return const Color(0xFFF59E0B);
      case 16:
        return const Color(0xFFFB923C);
      case 32:
        return const Color(0xFFF97316);
      case 64:
        return const Color(0xFFEF4444);
      case 128:
        return const Color(0xFF22C55E);
      case 256:
        return const Color(0xFF14B8A6);
      case 512:
        return const Color(0xFF06B6D4);
      case 1024:
        return const Color(0xFF3B82F6);
      default:
        return const Color(0xFF8B5CF6);
    }
  }
}

class _ControlPad extends StatelessWidget {
  const _ControlPad({required this.onMove});

  final Future<void> Function(MoveDirection direction) onMove;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ArrowButton(
          icon: Icons.keyboard_arrow_up,
          onPressed: () => onMove(MoveDirection.up),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ArrowButton(
              icon: Icons.keyboard_arrow_left,
              onPressed: () => onMove(MoveDirection.left),
            ),
            const SizedBox(width: 48),
            _ArrowButton(
              icon: Icons.keyboard_arrow_right,
              onPressed: () => onMove(MoveDirection.right),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _ArrowButton(
          icon: Icons.keyboard_arrow_down,
          onPressed: () => onMove(MoveDirection.down),
        ),
      ],
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
        minimumSize: const Size(64, 56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      onPressed: onPressed,
      child: Icon(icon, size: 32),
    );
  }
}
