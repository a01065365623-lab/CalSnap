import 'package:flutter/material.dart';

class LabeledNumberField extends StatelessWidget {
  final String label;
  final String suffix;
  final TextEditingController controller;
  final bool allowDecimal;

  const LabeledNumberField({
    super.key,
    required this.label,
    required this.suffix,
    required this.controller,
    this.allowDecimal = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: TextInputType.numberWithOptions(decimal: allowDecimal),
          decoration: InputDecoration(
            suffixText: suffix,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ],
    );
  }
}
