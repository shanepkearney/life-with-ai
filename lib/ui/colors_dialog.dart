import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../app/life_controller.dart';
import '../render/board_palette.dart';
import 'breakpoints.dart';
import 'theme.dart';

/// The board's colors: presets to pick with one tap, each color editable,
/// and a reset to Neon. Changes show on the board behind as you make them,
/// and are kept (on this device) as you go; there's nothing to confirm.
Future<void> showColorsDialog(BuildContext context, LifeController life) => showGeneralDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Close',
  // Light, so the board behind stays visible: it's the preview.
  barrierColor: Colors.black.withValues(alpha: 0.08),
  transitionDuration: const Duration(milliseconds: 200),
  pageBuilder: (context, _, _) => _ColorsPanel(life: life),
  transitionBuilder: (context, anim, _, child) => FadeTransition(opacity: anim, child: child),
);

/// A palette as a small bar: its five heat stops on its background.
class PaletteSwatch extends StatelessWidget {
  const PaletteSwatch(this.palette, {super.key, this.width = 56, this.height = 12});

  final BoardPalette palette;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: palette.background,
      borderRadius: BorderRadius.circular(height / 2),
      border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      gradient: LinearGradient(colors: palette.heat),
    ),
  );
}

class _ColorsPanel extends StatefulWidget {
  const _ColorsPanel({required this.life});

  final LifeController life;

  @override
  State<_ColorsPanel> createState() => _ColorsPanelState();
}

class _ColorsPanelState extends State<_ColorsPanel> {
  /// Which color the editor is on: stops 0-4, or 5 for the background.
  int _editing = 1;
  late final _hex = TextEditingController(text: '#${BoardPalette.hex(_color)}');

  static const _labels = ['Quiet', '', '', '', 'Crowded', 'Background'];

  BoardPalette get _palette => widget.life.palette;
  Color get _color => _palette.all[_editing];

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _choose(BoardPalette p) {
    widget.life.choosePalette(p);
    _syncHex();
  }

  void _setColor(Color c) {
    widget.life.choosePalette(_palette.withColor(_editing, c));
    _syncHex();
  }

  void _syncHex() {
    final text = '#${BoardPalette.hex(_color)}';
    if (_hex.text.toLowerCase() != text) _hex.text = text;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final phone = Breakpoints.isMobile(MediaQuery.sizeOf(context));
    final label = Neon.mono.copyWith(fontSize: 11, color: Neon.muted, letterSpacing: 1.2);
    final panel = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Material(
            color: const Color(0xD90B0E17),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: Neon.cyan.withValues(alpha: 0.25)),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 14, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Board colors',
                          style: Neon.mono.copyWith(fontSize: 16, fontWeight: FontWeight.bold, color: Neon.cyan),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded, color: Neon.muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('PRESETS', style: label),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [for (final p in BoardPalette.presets) _presetChip(p)]),
                  const SizedBox(height: 16),
                  Text(_palette.isPreset ? 'EDIT A COLOR' : 'EDIT A COLOR · CUSTOM', style: label),
                  const SizedBox(height: 8),
                  Row(children: [for (var i = 0; i < 6; i++) Expanded(child: _colorWell(i))]),
                  const SizedBox(height: 12),
                  _editor(),
                  const SizedBox(height: 16),
                  // How strongly crowded regions glow: 0 is none, 1 the default, 2 twice as bright.
                  Text('GLOW · ${widget.life.pipeline.glow.toStringAsFixed(1)}', style: label),
                  Slider(
                    value: widget.life.pipeline.glow,
                    max: 2,
                    divisions: 20,
                    onChanged: (v) {
                      widget.life.setGlow(v);
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: _palette == BoardPalette.neon ? null : () => _choose(BoardPalette.neon),
                        style: TextButton.styleFrom(foregroundColor: Neon.magenta),
                        icon: const Icon(Icons.restart_alt_rounded, size: 18),
                        label: Text('Reset to Neon', style: Neon.mono.copyWith(fontSize: 12, color: null)),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: FilledButton.styleFrom(backgroundColor: Neon.cyan, foregroundColor: Colors.black),
                        child: Text('Done', style: Neon.mono.copyWith(fontSize: 12, color: null, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return SafeArea(
      child: Align(
        // Centred on desktop, where the board shows around it; along the bottom on
        // phones, where a centred panel would hide most of the board it previews on.
        alignment: phone ? Alignment.bottomCenter : Alignment.center,
        child: Padding(padding: const EdgeInsets.all(16), child: panel),
      ),
    );
  }

  Widget _presetChip(BoardPalette p) {
    final selected = _palette == p;
    return Tooltip(
      message: p.name,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _choose(p),
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 7, 8, 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? Neon.cyan : Neon.border, width: selected ? 1.5 : 1),
            color: selected ? Neon.cyan.withValues(alpha: 0.08) : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PaletteSwatch(p, width: 88, height: 12),
              const SizedBox(height: 5),
              Text(p.name, style: Neon.mono.copyWith(fontSize: 11, color: selected ? Neon.cyan : Neon.text)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _colorWell(int i) {
    final selected = i == _editing;
    final name = i == 5 ? 'Background' : ['Quiet', 'Low', 'Middle', 'High', 'Crowded'][i];
    return Tooltip(
      message: name,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          _editing = i;
          _syncHex();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Column(
            children: [
              Container(
                height: 30,
                decoration: BoxDecoration(
                  color: _palette.all[i],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: selected ? Neon.cyan : Colors.white.withValues(alpha: 0.2), width: selected ? 2 : 1),
                  boxShadow: selected ? [BoxShadow(color: Neon.cyan.withValues(alpha: 0.35), blurRadius: 8)] : null,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _labels[i],
                style: Neon.mono.copyWith(fontSize: 9.5, color: Neon.muted),
                maxLines: 1,
                overflow: TextOverflow.visible,
                softWrap: false,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Hue, saturation and brightness sliders on tracks that show what each
  /// does, plus the hex code for exact colors.
  Widget _editor() {
    final hsv = HSVColor.fromColor(_color);
    Widget slider(String name, double value, double max, List<Color> track, ValueChanged<double> onChanged) => Row(
      children: [
        SizedBox(
          width: 78,
          child: Text(name, style: Neon.mono.copyWith(fontSize: 11, color: Neon.muted)),
        ),
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                height: 10,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5),
                  gradient: LinearGradient(colors: track),
                ),
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: Colors.transparent,
                  inactiveTrackColor: Colors.transparent,
                  thumbColor: Colors.white,
                  overlayColor: Colors.white.withValues(alpha: 0.1),
                ),
                child: Slider(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  value: value.clamp(0, max),
                  max: max,
                  onChanged: onChanged,
                  semanticFormatterCallback: (v) => '$name ${v.round()}',
                ),
              ),
            ],
          ),
        ),
      ],
    );
    return Column(
      children: [
        slider('Hue', hsv.hue, 360, [
          for (var h = 0; h <= 360; h += 60) HSVColor.fromAHSV(1, h.toDouble(), 1, 1).toColor(),
        ], (v) => _setColor(hsv.withHue(v).toColor())),
        slider('Saturation', hsv.saturation * 100, 100, [
          hsv.withSaturation(0).toColor(),
          hsv.withSaturation(1).toColor(),
        ], (v) => _setColor(hsv.withSaturation(v / 100).toColor())),
        slider('Brightness', hsv.value * 100, 100, [Colors.black, hsv.withValue(1).toColor()], (v) => _setColor(hsv.withValue(v / 100).toColor())),
        Row(
          children: [
            SizedBox(
              width: 78,
              child: Text('Hex', style: Neon.mono.copyWith(fontSize: 11, color: Neon.muted)),
            ),
            SizedBox(
              width: 110,
              child: TextField(
                controller: _hex,
                style: Neon.mono.copyWith(fontSize: 12),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (s) {
                  final c = BoardPalette.parseHex(s);
                  c == null ? _syncHex() : _setColor(c);
                },
                onChanged: (s) {
                  final c = BoardPalette.parseHex(s);
                  if (c != null && BoardPalette.hex(c) != BoardPalette.hex(_color)) widget.life.choosePalette(_palette.withColor(_editing, c));
                  setState(() {});
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}
