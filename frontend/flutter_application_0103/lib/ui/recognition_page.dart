import 'package:flutter/material.dart';

import 'shared_widgets.dart';

class RecognitionPage extends StatelessWidget {
  const RecognitionPage({
    super.key,
    required this.textMode,
    required this.textController,
    required this.onParseText,
  });

  final bool textMode;
  final TextEditingController textController;
  final VoidCallback onParseText;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (textMode) ...[
            _InputCard(
              textController: textController,
              onParseText: onParseText,
            ),
            const SizedBox(height: 20),
          ],
          const SectionTitle(
            title: '语音纪要',
            subtitle: '完成录音后会直接生成可编辑事项',
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

class _InputCard extends StatelessWidget {
  const _InputCard({
    required this.textController,
    required this.onParseText,
  });

  final TextEditingController textController;
  final VoidCallback onParseText;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: _buildTextInput(context),
      ),
    );
  }

  Widget _buildTextInput(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '文字输入',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: textController,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: '例：明早 9 点给客户打电话，周三下午提交报告。',
            filled: true,
            fillColor: const Color(0xFFF8F5F1),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: onParseText,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('生成事项'),
          ),
        ),
      ],
    );
  }
}
