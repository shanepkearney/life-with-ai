import '../core/grid.dart';
import 'cpu_stepper.dart';

CpuStepper create() => _InlineStepper();

class _InlineStepper implements CpuStepper {
  StepperState? _state;

  @override
  Future<void> load(Grid grid) async => _state = StepperState(grid);

  @override
  Future<StepResult> step(int generations) async => _state!.advance(generations);

  @override
  Future<Grid> snapshot() async => _state!.a.copy();

  @override
  void dispose() {}
}
