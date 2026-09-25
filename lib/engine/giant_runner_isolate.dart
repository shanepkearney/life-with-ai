import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'giant_runner.dart';

GiantRunner create() => _IsolateGiantRunner();

/// Natively: the plane lives in its own isolate, so a jump of a million
/// generations never stalls the UI. Frames come back as transferable bytes.
class _IsolateGiantRunner implements GiantRunner {
  _IsolateGiantRunner() {
    _ready = _spawn();
  }

  late final Future<SendPort> _ready;
  final _replies = ReceivePort();
  final _pending = <Completer<Object?>>[];
  Isolate? _isolate;

  @override
  bool get inline => false;

  Future<SendPort> _spawn() async {
    final handshake = Completer<SendPort>();
    _replies.listen((msg) {
      if (msg is SendPort) {
        handshake.complete(msg);
      } else if (msg case ('error', String e)) {
        _pending.removeAt(0).completeError(StateError(e));
      } else {
        _pending.removeAt(0).complete(msg);
      }
    });
    _isolate = await Isolate.spawn(_worker, _replies.sendPort, debugName: 'giant-hashlife');
    return handshake.future;
  }

  Future<GiantFrame> _call(Object message) async {
    final port = await _ready;
    final c = Completer<Object?>();
    _pending.add(c);
    port.send(message);
    final (TransferableTypedData t, int w, int h, int gen, int pop, List<int>? b) = await c.future as (TransferableTypedData, int, int, int, int, List<int>?);
    return (
      rgba: t.materialize().asUint8List(),
      width: w,
      height: h,
      generation: gen,
      population: pop,
      bounds: b == null ? null : (x: b[0], y: b[1], width: b[2], height: b[3]),
    );
  }

  static List<int> _view(GiantView v) => [v.left, v.top, v.k, v.width, v.height];

  @override
  Future<GiantFrame> load(Int32List cells, GiantView view) => _call(('load', TransferableTypedData.fromList([cells]), _view(view)));

  @override
  Future<GiantFrame> advance(int j, GiantView view) => _call(('advance', j, _view(view)));

  @override
  Future<GiantFrame> render(GiantView view) => _call(('render', _view(view)));

  @override
  Future<GiantFrame> restart(GiantView view) => _call(('restart', _view(view)));

  @override
  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _replies.close();
  }
}

void _worker(SendPort out) {
  final inbox = ReceivePort();
  out.send(inbox.sendPort);
  GiantWorld? world;
  void reply(List<int> v) {
    final f = world!.draw((left: v[0], top: v[1], k: v[2], width: v[3], height: v[4]));
    final b = f.bounds;
    out.send((TransferableTypedData.fromList([f.rgba]), f.width, f.height, f.generation, f.population, b == null ? null : [b.x, b.y, b.width, b.height]));
  }

  inbox.listen((msg) {
    // A failure answers its request, so the app is never left waiting on it.
    try {
      switch (msg) {
        case ('load', TransferableTypedData t, List<int> v):
          world = GiantWorld(t.materialize().asInt32List());
          reply(v);
        case ('advance', int j, List<int> v):
          world!.plane.advance(j);
          reply(v);
        case ('render', List<int> v):
          reply(v);
        case ('restart', List<int> v):
          world!.plane.restart();
          reply(v);
      }
    } catch (e) {
      out.send(('error', '$e'));
    }
  });
}
