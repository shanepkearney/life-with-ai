import 'dart:typed_data';
import 'dart:ui' as ui;

/// Compiled fragment programs, loaded once at startup and shared.
class Shaders {
  Shaders._(this.lifeStep, this.trail, this.density, this.composite);

  final ui.FragmentProgram lifeStep;
  final ui.FragmentProgram trail;
  final ui.FragmentProgram density;
  final ui.FragmentProgram composite;

  static Future<Shaders> load() async {
    final programs = await Future.wait([
      ui.FragmentProgram.fromAsset('shaders/life_step.frag'),
      ui.FragmentProgram.fromAsset('shaders/trail.frag'),
      ui.FragmentProgram.fromAsset('shaders/density.frag'),
      ui.FragmentProgram.fromAsset('shaders/composite.frag'),
    ]);
    return Shaders._(programs[0], programs[1], programs[2], programs[3]);
  }
}

/// Runs [shader] over a fresh [width]x[height] target and returns the result
/// as a GPU-resident image. `toImageSync` never reads back to the CPU, which is
/// what makes GPU ping-pong viable in Flutter.
ui.Image renderPass(ui.FragmentShader shader, int width, int height) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), ui.Paint()..shader = shader);
  final picture = recorder.endRecording();
  final image = picture.toImageSync(width, height);
  picture.dispose();
  return image;
}

/// How many chained passes to allow before [detach]ing: short enough that
/// freeing a chain is always cheap, long enough that detaching costs nothing.
const detachEvery = 128;

/// A copy of [image] that stands on its own.
///
/// A `toImageSync` image is deferred: it keeps the drawing that produced it,
/// and so every image that drawing sampled. Ping-pong passes (the GPU engine,
/// the glow trail) therefore build a chain one link longer per pass, and
/// freeing the newest image frees the whole chain recursively on the raster
/// thread. After a few thousand passes that recursion overflows its stack and
/// the app crashes, e.g. when a board is replaced after a long run.
/// `Picture.toImage` rasterizes now and keeps nothing, so its result starts a
/// fresh chain. Drawn 1:1 with `BlendMode.src`, the pixels are exact.
Future<ui.Image> detach(ui.Image image) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawImage(
    image,
    ui.Offset.zero,
    ui.Paint()
      ..blendMode = ui.BlendMode.src
      ..filterQuality = ui.FilterQuality.none,
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(image.width, image.height);
  } finally {
    picture.dispose();
  }
}

/// Uploads raw RGBA pixels as an image.
Future<ui.Image> imageFromRgba(Uint8List rgba, int width, int height) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
  final descriptor = ui.ImageDescriptor.raw(buffer, width: width, height: height, pixelFormat: ui.PixelFormat.rgba8888);
  final codec = await descriptor.instantiateCodec();
  final frame = await codec.getNextFrame();
  codec.dispose();
  descriptor.dispose();
  buffer.dispose();
  return frame.image;
}

/// A solid black image, used to initialize feedback buffers.
ui.Image blackImage(int width, int height) {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), ui.Paint()..color = const ui.Color(0xFF000000));
  final picture = recorder.endRecording();
  final image = picture.toImageSync(width, height);
  picture.dispose();
  return image;
}
