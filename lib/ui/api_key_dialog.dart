import 'package:flutter/material.dart';

import '../ai/anthropic_client.dart';
import '../app/assistant_controller.dart';
import 'theme.dart';

Future<void> showApiKeyDialog(BuildContext context, AssistantController assistant) =>
    showDialog(context: context, builder: (_) => _ApiKeyDialog(assistant));

class _ApiKeyDialog extends StatefulWidget {
  const _ApiKeyDialog(this.assistant);
  final AssistantController assistant;

  @override
  State<_ApiKeyDialog> createState() => _ApiKeyDialogState();
}

class _ApiKeyDialogState extends State<_ApiKeyDialog> {
  late final _key = TextEditingController(text: widget.assistant.apiKey);
  late ClaudeModel _model = widget.assistant.model;
  late bool _remember = widget.assistant.rememberKey;
  bool _obscure = true;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0B0E17),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Neon.border),
      ),
      title: const Text('Assistant settings'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _key,
              obscureText: _obscure,
              autofocus: true,
              style: Neon.mono,
              decoration: InputDecoration(
                labelText: 'Anthropic API key',
                hintText: 'sk-ant-…',
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<ClaudeModel>(
              initialValue: _model,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Model'),
              items: [
                for (final m in ClaudeModel.values)
                  DropdownMenuItem(
                    value: m,
                    child: Text(
                      '${m.label}  ·  \$${m.inputPerMTok.toStringAsFixed(0)} / \$${m.outputPerMTok.toStringAsFixed(0)} per MTok',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (m) => setState(() => _model = m!),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _remember,
              onChanged: (v) => setState(() => _remember = v!),
              title: const Text('Remember the key on this device'),
              subtitle: Text(
                'Stored unencrypted in app storage (localStorage on web). Leave off on shared machines. '
                'The key is sent only to api.anthropic.com.',
                style: Neon.mono.copyWith(color: Neon.muted, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            widget.assistant.saveSettings(key: _key.text, model: _model, remember: _remember);
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
