import 'dart:math';

enum MoveDirection { up, down, left, right }

class TileGame {
  TileGame({this.size = 4, Random? random}) : _random = random ?? Random() {
    reset();
  }

  final int size;
  final Random _random;

  late List<List<int>> board;
  int score = 0;

  void reset() {
    score = 0;
    board = List.generate(size, (_) => List.filled(size, 0));
    _spawnRandomTile();
    _spawnRandomTile();
  }

  void setBoard(List<List<int>> newBoard) {
    board = newBoard.map((row) => List<int>.from(row)).toList();
  }

  bool move(MoveDirection direction, {bool spawnNewTile = true}) {
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
      return false;
    }

    score += gainedScore;
    if (spawnNewTile) {
      _spawnRandomTile();
    }
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
