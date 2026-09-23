# Life with AI

Conway's Game of Life in Flutter, with a shader-driven neon glow that heats up where cells
congregate, and (in progress) an AI assistant that seeds the board to produce the outcome you
describe.

A reimagining of [shanepkearney/life](https://github.com/shanepkearney/life), a Java/Swing
implementation. It keeps the original's rules and toroidal (wrap-around) board, and its
1024×768 board is one of the size presets.

## Architecture

```
lib/core      Grid (toroidal, Uint8List) + RLE pattern library. Pure Dart, no Flutter.
lib/engine    LifeEngine interface with two interchangeable implementations:
                CpuEngine  - steps in a background isolate (inline on web), uploads a texture
                GpuEngine  - steps with a fragment shader, ping-ponging GPU-resident images
lib/render    GlowPipeline: trail (persistence) + density (hotspot) passes, then composite
shaders/      life_step, trail, density, composite (GLSL, compiled by Flutter)
lib/app       LifeController: play/pause, speed, engine hot-swap, drawing
lib/ui        Canvas, HUD, control bar
```

Both engines emit the same thing: one pixel per cell as a `ui.Image`. The renderer therefore
never knows which engine produced a frame, and the engines can be swapped mid-run from the
control bar to compare throughput on the same pattern.

### Why two engines

| | CPU isolate | GPU shader |
|---|---|---|
| Throughput | bounded by Dart loop + texture upload per frame | one draw call per generation, no upload |
| Testability | trivially unit-testable | verified against the CPU by a parity test |
| Readback | free (board lives in Dart) | `toByteData` stalls the GPU, so it is throttled |
| Web | runs on the main thread (no isolates) | same as native |

`test/engine/engine_parity_test.dart` requires the GPU engine to match the CPU rules
bit-for-bit, including odd board sizes and wrap-around at the edges.

### Hotspot glow

`density.frag` computes local population density at quarter resolution (64 bilinear taps
covering 16×16 cells). `composite.frag` maps that density through a violet → cyan → magenta
→ amber → white heat ramp, adds a fading trail buffer, and draws live cells tinted by how
crowded their neighbourhood is.

## Run

```bash
flutter run -d macos
flutter run -d chrome
flutter test
```

Dev flags: `--dart-define=AUTOPLAY=true` starts running; `--dart-define=ENGINE=cpu` starts on
the CPU engine.

Controls: space = play/pause; drag on the board to draw (toggle the pencil to erase).
