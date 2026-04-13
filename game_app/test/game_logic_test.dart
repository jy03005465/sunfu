import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_app/game_logic.dart';

void main() {
  group('TileGame', () {
    test('moving left merges adjacent tiles once', () {
      final game = TileGame(random: Random(0));
      game.restore(
        board: [
          [2, 2, 2, 0],
          [0, 0, 0, 0],
          [0, 0, 0, 0],
          [0, 0, 0, 0],
        ],
        score: 0,
      );

      final result = game.move(MoveDirection.left, spawnNewTile: false);

      expect(result.changed, isTrue);
      expect(result.gainedScore, equals(4));
      expect(game.board.first, equals([4, 2, 0, 0]));
      expect(game.score, equals(4));
      expect(game.canUndo, isTrue);
    });

    test('moving right pushes tiles to edge before merging', () {
      final game = TileGame(random: Random(0));
      game.restore(
        board: [
          [2, 0, 2, 2],
          [0, 0, 0, 0],
          [0, 0, 0, 0],
          [0, 0, 0, 0],
        ],
        score: 0,
      );

      game.move(MoveDirection.right, spawnNewTile: false);

      expect(game.board.first, equals([0, 0, 2, 4]));
      expect(game.score, equals(4));
    });

    test('undo restores previous board and score', () {
      final game = TileGame(random: Random(0));
      game.restore(
        board: [
          [2, 2, 0, 0],
          [0, 0, 0, 0],
          [0, 0, 0, 0],
          [0, 0, 0, 0],
        ],
        score: 12,
      );

      game.move(MoveDirection.left, spawnNewTile: false);
      final undone = game.undo();

      expect(undone, isTrue);
      expect(game.board.first, equals([2, 2, 0, 0]));
      expect(game.score, equals(12));
      expect(game.canUndo, isFalse);
    });

    test('detects game over when no moves remain', () {
      final game = TileGame(random: Random(0));
      game.restore(
        board: [
          [2, 4, 2, 4],
          [4, 2, 4, 2],
          [2, 4, 2, 4],
          [4, 2, 4, 8],
        ],
        score: 0,
      );

      expect(game.canMove, isFalse);
      expect(game.isGameOver, isTrue);
    });

    test('detects available move when equal neighbors exist', () {
      final game = TileGame(random: Random(0));
      game.restore(
        board: [
          [2, 4, 2, 4],
          [4, 2, 4, 2],
          [2, 4, 4, 8],
          [4, 2, 8, 16],
        ],
        score: 0,
      );

      expect(game.canMove, isTrue);
      expect(game.isGameOver, isFalse);
    });

    test('snapshot exports state for persistence', () {
      final game = TileGame(random: Random(0));
      game.restore(
        board: [
          [2, 4, 0, 0],
          [8, 16, 0, 0],
          [0, 0, 0, 0],
          [0, 0, 0, 0],
        ],
        score: 128,
      );

      final snapshot = game.snapshot();

      expect(snapshot.score, equals(128));
      expect(snapshot.board[1], equals([8, 16, 0, 0]));
    });
  });
}
