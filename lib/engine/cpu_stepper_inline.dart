import '../core/grid.dart';
import 'cpu_stepper.dart';

CpuStepper create({bool hashLife = false}) => _InlineStepper(hashLife);

class _InlineStepper implements CpuStepper {
  _InlineStepper(this._hashLife);

  final bool _hashLife;
  Stepping? _state;

  @override
  Future<void> load(Grid grid) async => _state = Stepping(grid, hashLife: _hashLife);

  @override
  Future<StepResult> step(int generations) async => _state!.advance(generations);

  @override
  Future<Grid> snapshot() async => _state!.board.copy();

  @override
  void dispose() {}
}
