import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_app/game_logic.dart';

void main() {
  group('TileGame', () {
    test('moving left merges adjacent tiles once', () {
      final game = TileGame(random: Random(0));
      game.setBoard([
        [2, 2, 2, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
      ]);

      final changed = game.move(MoveDirection.left, spawnNewTile: false);

      expect(changed, isTrue);
      expect(game.board.first, equals([4, 2, 0, 0]));
      expect(game.score, equals(4));
    });

    test('moving right pushes tiles to edge before merging', () {
      final game = TileGame(random: Random(0));
      game.setBoard([
        [2, 0, 2, 2],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
      ]);

      game.move(MoveDirection.right, spawnNewTile: false);

      expect(game.board.first, equals([0, 0, 2, 4]));
      expect(game.score, equals(4));
    });

    test('detects game over when no moves remain', () {
      final game = TileGame(random: Random(0));
      game.setBoard([
        [2, 4, 2, 4],
        [4, 2, 4, 2],
        [2, 4, 2, 4],
        [4, 2, 4, 8],
      ]);

      expect(game.canMove, isFalse);
      expect(game.isGameOver, isTrue);
    });

    test('detects available move when equal neighbors exist', () {
      final game = TileGame(random: Random(0));
      game.setBoard([
        [2, 4, 2, 4],
        [4, 2, 4, 2],
        [2, 4, 4, 8],
        [4, 2, 8, 16],
      ]);

      expect(game.canMove, isTrue);
      expect(game.isGameOver, isFalse);
    });
  });
}
