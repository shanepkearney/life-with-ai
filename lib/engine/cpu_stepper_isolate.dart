import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../core/grid.dart';
import '../core/life_rule.dart';
import 'cpu_stepper.dart';

CpuStepper create({bool hashLife = false}) => _IsolateStepper(hashLife);

/// Messages are records sent over a SendPort; the board travels as
/// TransferableTypedData so a 3 MB frame is moved, not copied.
class _IsolateStepper implements CpuStepper {
  _IsolateStepper(this._hashLife) {
    _ready = _spawn();
  }

  final bool _hashLife;

  late final Future<SendPort> _ready;
  final _replies = ReceivePort();
  final _pending = <Completer<Object?>>[];
  Isolate? _isolate;

  Future<SendPort> _spawn() async {
    final handshake = Completer<SendPort>();
    _replies.listen((msg) {
      if (msg is SendPort) {
        handshake.complete(msg);
      } else {
        _pending.removeAt(0).complete(msg);
      }
    });
    _isolate = await Isolate.spawn(_worker, _replies.sendPort, debugName: 'life-stepper');
    return handshake.future;
  }

  Future<Object?> _call(Object message) async {
    final port = await _ready;
    final c = Completer<Object?>();
    _pending.add(c); // replies arrive in order, so a FIFO is enough
    port.send(message);
    return c.future;
  }

  @override
  Future<void> load(Grid grid, LifeRule rule) =>
      _call(('load', grid.width, grid.height, _hashLife, rule.birth, rule.survival, TransferableTypedData.fromList([grid.cells])));

  @override
  Future<StepResult> step(int generations) async {
    final (TransferableTypedData t, int pop) = await _call(('step', generations)) as (TransferableTypedData, int);
    return (rgba: t.materialize().asUint8List(), population: pop);
  }

  @override
  Future<Grid> snapshot() async {
    final (int w, int h, TransferableTypedData t) = await _call(('snapshot',)) as (int, int, TransferableTypedData);
    return Grid.fromCells(w, h, t.materialize().asUint8List());
  }

  @override
  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _replies.close();
  }
}

void _worker(SendPort out) {
  final inbox = ReceivePort();
  out.send(inbox.sendPort);
  Stepping? state;
  inbox.listen((msg) {
    switch (msg) {
      case ('load', int w, int h, bool hashLife, int birth, int survival, TransferableTypedData t):
        // HashLife keeps its table of squares between loads only within one board.
        state = Stepping(Grid.fromCells(w, h, t.materialize().asUint8List()), hashLife: hashLife, rule: LifeRule(birth, survival));
        out.send(null);
      case ('step', int n):
        final r = state!.advance(n);
        out.send((TransferableTypedData.fromList([r.rgba]), r.population));
      case ('snapshot',):
        final g = state!.board;
        out.send((g.width, g.height, TransferableTypedData.fromList([Uint8List.fromList(g.cells)])));
    }
  });
}
