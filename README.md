# Life with AI

Conway's Game of Life in Flutter, with a shader-driven neon glow that heats up where cells
congregate, and an AI assistant that designs a starting pattern to produce the outcome you describe.

**Live: https://shanepkearney.github.io/life-with-ai/** (bring your own Anthropic API key for
the assistant; the simulation works without one).

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
lib/ai        Seed agent: Anthropic client (raw HTTP), tool loop, sandbox tools, simulator
lib/app       LifeController (play/pause, speed, engine hot-swap, drawing) + AssistantController
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

## The seed assistant

You describe an outcome ("two glider fleets collide and explode into colour"), and Claude
builds a seed, simulates it, reads the result, and refines it. You can watch it working on the
board.

**It's an agent loop, not one-shot generation.** LLMs are poor at predicting Game of Life
dynamics, but good at planning and at reading feedback. So the model gets tools and checks its
own work:

| Tool | Purpose |
|---|---|
| `place_pattern` | stamp a named pattern (glider, Gosper gun, pulsar, acorn…) with rotation and flip |
| `draw_shape` | lines, rectangles, ellipses, seeded random soup |
| `set_cells` / `clear_board` | fine edits |
| `view_board` | ASCII of the seed, whole board or a 1:1 region |
| `simulate` | run forward without changing the seed; returns its fate (dies / still life / period-N / growing), a population curve, hotspot counts and ASCII thumbnails |
| `simulate(include_image)` | adds a PNG of the final board when the shape matters (≈ w×h/750 tokens, ~260 for 512×384) |
| `finish` | hand the seed to the board and start playing |

Design choices:

- **The pattern library is tested.** Every claim the model relies on (glider heading, gun
  cadence, oscillator periods, diehard's 130 generations) is asserted in `test/core`. Writing
  those tests caught that the standard RLE spaceships travel *left*; they are now mirrored.
- **Simulation runs on the CPU grid, off the UI thread** (`compute`), independent of which
  engine draws the board.
- **Every experiment is replayed for the user.** `simulate` computes instantly, so Claude gets
  its report straight away. Meanwhile the board replays the same run, fast-forwarded to about 8s
  and stopping on the exact generation Claude inspected, while the next API call is in flight.
  The playback therefore adds no waiting. Queued runs play in order, and the final seed takes
  over when they end.
- **Bad tool input returns an `is_error` result**, so the model corrects itself rather than
  the loop crashing.
- **Guardrails for a user-supplied key:** at most 10 model turns per request, a live cost
  meter (cache-aware), and a Stop button. The system prompt and tools are a stable prefix
  with `cache_control`, so each refine turn re-reads them at 0.1× cost.
- **Model:** Claude Opus 5 by default (Sonnet 5 selectable), adaptive thinking with
  summarised reasoning shown in the chat, and server-side refusal fallbacks enabled.
- **Key handling:** the user pastes their own key. It is sent only to `api.anthropic.com`,
  with the direct-browser-access header the web build needs, and is kept in memory unless
  "remember" is ticked (then stored unencrypted in app storage, as the dialog says).

`test/ai/seed_agent_test.dart` drives the whole loop against scripted API responses: tool
results are batched in order, thinking blocks are echoed back unchanged, roles still alternate
on follow-ups, the turn cap holds, and the required headers and cache settings are present.

## Run

```bash
flutter run -d macos
flutter run -d chrome
flutter test
```

Dev flags: `--dart-define=AUTOPLAY=true` starts running; `--dart-define=ENGINE=cpu` starts on
the CPU engine.

Speed is a rate in generations per second (1–960, geometric steps), not "generations per frame",
so it runs the same on 60 Hz and 120 Hz displays; `test/app_speed_test.dart` checks both.

Controls: space = play/pause; drag on the board to draw (toggle the pencil to erase).
