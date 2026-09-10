import 'package:flutter/material.dart';
import '../core/constants/national_metros.dart';
import '../core/theme/app_colors.dart';

/// Every district picker in this app is scoped to the 5 national metros —
/// no single-state district list anywhere.
class DistrictDropdown extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final String? label;

  const DistrictDropdown({super.key, required this.value, required this.onChanged, this.label});

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      dropdownColor: AppColors.surfaceHigh,
      borderRadius: BorderRadius.circular(16),
      icon: const Icon(Icons.expand_more_rounded, color: AppColors.textTertiary),
      decoration: InputDecoration(labelText: label ?? 'City'),
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
      items: NationalMetros.names
          .map((name) => DropdownMenuItem(value: name, child: Text(name)))
          .toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}
