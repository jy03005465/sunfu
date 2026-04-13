import 'dart:math';

enum MoveDirection { up, down, left, right }

class MoveResult {
  const MoveResult({required this.changed, required this.gainedScore});

  final bool changed;
  final int gainedScore;
}

class GameSnapshot {
  const GameSnapshot({
    required this.board,
    required this.score,
    required this.moveCount,
  });

  final List<List<int>> board;
  final int score;
  final int moveCount;

  Map<String, dynamic> toMap() {
    return {
      'board': board.map((row) => List<int>.from(row)).toList(),
      'score': score,
      'moveCount': moveCount,
    };
  }

  factory GameSnapshot.fromMap(Map<String, dynamic> map) {
    final rawBoard = map['board'];
    if (rawBoard is! List) {
      throw const FormatException('Missing board in snapshot.');
    }

    final board = rawBoard.map<List<int>>((row) {
      if (row is! List) {
        throw const FormatException('Invalid board row in snapshot.');
      }
      return row.map<int>((value) => value as int).toList();
    }).toList();

    return GameSnapshot(
      board: board,
      score: map['score'] as int? ?? 0,
      moveCount: map['moveCount'] as int? ?? 0,
    );
  }
}

typedef BoardSnapshot = GameSnapshot;

class TileGame {
  TileGame({this.size = 4, Random? random}) : _random = random ?? Random() {
    reset();
  }

  factory TileGame.fromJson(Map<String, dynamic> json, {Random? random}) {
    final game = TileGame(random: random);
    final snapshot = GameSnapshot.fromMap(json);
    game.restore(snapshot: snapshot);
    return game;
  }

  final int size;
  final Random _random;

  late List<List<int>> board;
  int score = 0;
  int moveCount = 0;
  GameSnapshot? _undoSnapshot;

  void reset() {
    score = 0;
    moveCount = 0;
    _undoSnapshot = null;
    board = List.generate(size, (_) => List.filled(size, 0));
    _spawnRandomTile();
    _spawnRandomTile();
  }

  void setBoard(List<List<int>> newBoard, {int score = 0, int moveCount = 0}) {
    _validateBoard(newBoard);
    board = _cloneBoard(newBoard);
    this.score = score;
    this.moveCount = moveCount;
  }

  void restore({
    GameSnapshot? snapshot,
    List<List<int>>? board,
    int score = 0,
    int moveCount = 0,
  }) {
    final resolvedSnapshot =
        snapshot ??
        GameSnapshot(
          board: board ?? List.generate(size, (_) => List.filled(size, 0)),
          score: score,
          moveCount: moveCount,
        );

    _validateBoard(resolvedSnapshot.board);
    this.board = _cloneBoard(resolvedSnapshot.board);
    this.score = resolvedSnapshot.score;
    this.moveCount = resolvedSnapshot.moveCount;
    _undoSnapshot = null;
  }

  GameSnapshot snapshot() {
    return GameSnapshot(
      board: _cloneBoard(board),
      score: score,
      moveCount: moveCount,
    );
  }

  Map<String, dynamic> toJson() => snapshot().toMap();

  int get highestTile {
    var highest = 0;
    for (final row in board) {
      for (final value in row) {
        if (value > highest) {
          highest = value;
        }
      }
    }
    return highest;
  }

  bool get isFreshGame => score == 0 && moveCount == 0;
  bool get canUndo => _undoSnapshot != null;

  MoveResult move(MoveDirection direction, {bool spawnNewTile = true}) {
    final previousBoard = _cloneBoard(board);
    var gainedScore = 0;

    switch (direction) {
      case MoveDirection.left:
        for (var row = 0; row < size; row++) {
          final result = _collapseLine(board[row]);
          board[row] = result.$1;
          gainedScore += result.$2;
        }
      case MoveDirection.right:
        for (var row = 0; row < size; row++) {
          final result = _collapseLine(board[row].reversed.toList());
          board[row] = result.$1.reversed.toList();
          gainedScore += result.$2;
        }
      case MoveDirection.up:
        for (var column = 0; column < size; column++) {
          final values = List.generate(size, (row) => board[row][column]);
          final result = _collapseLine(values);
          for (var row = 0; row < size; row++) {
            board[row][column] = result.$1[row];
          }
          gainedScore += result.$2;
        }
      case MoveDirection.down:
        for (var column = 0; column < size; column++) {
          final values = List.generate(
            size,
            (row) => board[row][column],
          ).reversed.toList();
          final result = _collapseLine(values);
          final restored = result.$1.reversed.toList();
          for (var row = 0; row < size; row++) {
            board[row][column] = restored[row];
          }
          gainedScore += result.$2;
        }
    }

    final changed = !_sameBoard(previousBoard, board);
    if (!changed) {
      return const MoveResult(changed: false, gainedScore: 0);
    }

    _undoSnapshot = GameSnapshot(
      board: previousBoard,
      score: score,
      moveCount: moveCount,
    );
    score += gainedScore;
    moveCount += 1;
    if (spawnNewTile) {
      _spawnRandomTile();
    }
    return MoveResult(changed: true, gainedScore: gainedScore);
  }

  bool undo() {
    final snapshot = _undoSnapshot;
    if (snapshot == null) {
      return false;
    }

    board = _cloneBoard(snapshot.board);
    score = snapshot.score;
    moveCount = snapshot.moveCount;
    _undoSnapshot = null;
    return true;
  }

  bool get hasWon {
    for (final row in board) {
      for (final value in row) {
        if (value >= 2048) {
          return true;
        }
      }
    }
    return false;
  }

  bool get canMove {
    if (_emptyCells().isNotEmpty) {
      return true;
    }

    for (var row = 0; row < size; row++) {
      for (var column = 0; column < size; column++) {
        final current = board[row][column];
        if (row + 1 < size && board[row + 1][column] == current) {
          return true;
        }
        if (column + 1 < size && board[row][column + 1] == current) {
          return true;
        }
      }
    }

    return false;
  }

  bool get isGameOver => !canMove;

  (List<int>, int) _collapseLine(List<int> values) {
    final compact = values.where((value) => value != 0).toList();
    final result = <int>[];
    var gainedScore = 0;
    var index = 0;

    while (index < compact.length) {
      if (index + 1 < compact.length && compact[index] == compact[index + 1]) {
        final merged = compact[index] * 2;
        result.add(merged);
        gainedScore += merged;
        index += 2;
      } else {
        result.add(compact[index]);
        index += 1;
      }
    }

    while (result.length < size) {
      result.add(0);
    }

    return (result, gainedScore);
  }

  void _spawnRandomTile() {
    final emptyCells = _emptyCells();
    if (emptyCells.isEmpty) {
      return;
    }

    final selected = emptyCells[_random.nextInt(emptyCells.length)];
    board[selected.$1][selected.$2] = _random.nextDouble() < 0.9 ? 2 : 4;
  }

  List<(int, int)> _emptyCells() {
    final result = <(int, int)>[];
    for (var row = 0; row < size; row++) {
      for (var column = 0; column < size; column++) {
        if (board[row][column] == 0) {
          result.add((row, column));
        }
      }
    }
    return result;
  }

  List<List<int>> _cloneBoard(List<List<int>> input) {
    return input.map((row) => List<int>.from(row)).toList();
  }

  void _validateBoard(List<List<int>> input) {
    if (input.length != size) {
      throw const FormatException('Board size does not match game size.');
    }
    for (final row in input) {
      if (row.length != size) {
        throw const FormatException('Board row size does not match game size.');
      }
    }
  }

  bool _sameBoard(List<List<int>> left, List<List<int>> right) {
    for (var row = 0; row < size; row++) {
      for (var column = 0; column < size; column++) {
        if (left[row][column] != right[row][column]) {
          return false;
        }
      }
    }
    return true;
  }
}
