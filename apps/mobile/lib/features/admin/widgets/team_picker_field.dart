/// حقل اسم فريق مع اقتراحات — يقبل أي نص، حتى ما ليس في الكتالوج.
///
/// كان خاصًا بشاشة إضافة المباراة، ونُقل إلى هنا حين انفصلت شاشتا
/// التعديل والحذف: ثلاث شاشات تعرض الحقل نفسه، فنسخه ثلاث مرات يعني أن
/// إصلاح سلوكه في واحدة يتركه معطوبًا في اثنتين.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';

import '../../competition/team_registry.dart';

/// حقل نصي مع اقتراحات فرق مفلترة — أي نص يُقبل، حتى لو لم يكن ضمن السجل.
class TeamPickerField extends StatelessWidget {
  /// ينشئ الحقل.
  const TeamPickerField({
    super.key,
    required this.fieldKey,
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.enabled,
    required this.optionsBuilder,
    this.catalog = const <TeamDto>[],
    this.onChanged,
  });

  /// مفتاح حقل النص نفسه (للاختبارات).
  final Key fieldKey;

  /// المتحكّم بالنص المكتوب.
  final TextEditingController controller;

  /// عقدة التركيز الخاصة بالحقل.
  final FocusNode focusNode;

  /// عنوان الحقل.
  final String label;

  /// هل الحقل قابل للتحرير.
  final bool enabled;

  /// مولّد الاقتراحات حسب النص المكتوب.
  final Iterable<String> Function(String query) optionsBuilder;

  /// The real `football_data.teams` catalog — an option matching one of
  /// these by name (case-insensitive) is a genuine team: selecting it is
  /// what lets the fixture link a real team id, shown here as a small hint
  /// distinguishing it from a legacy free-text-only name.
  final List<TeamDto> catalog;

  /// يُستدعى عند كل تغيير في النص أو عند اختيار اقتراح.
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return RawAutocomplete<String>(
          textEditingController: controller,
          focusNode: focusNode,
          optionsBuilder: (TextEditingValue value) =>
              optionsBuilder(value.text),
          onSelected: (String selection) {
            controller.text = selection;
            onChanged?.call();
          },
          fieldViewBuilder: (context, fieldController, fieldFocusNode, _) {
            return TextField(
              key: fieldKey,
              controller: fieldController,
              focusNode: fieldFocusNode,
              decoration: InputDecoration(
                labelText: label,
                border: const OutlineInputBorder(),
              ),
              enabled: enabled,
              onChanged: (_) => onChanged?.call(),
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            final List<String> optionList = options.toList();
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth,
                    maxHeight: 240,
                  ),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: optionList.length,
                    itemBuilder: (context, index) {
                      final String option = optionList[index];
                      final TeamBrand? brand =
                          kEplTeams[option] ?? kSaudiTeams[option];
                      final bool isCatalogTeam = catalog.any(
                        (TeamDto t) =>
                            t.name.toLowerCase() == option.toLowerCase(),
                      );
                      return ListTile(
                        dense: true,
                        title: Text(option),
                        subtitle: isCatalogTeam
                            ? const Text('team id مرتبط ✓')
                            : (brand == null ? null : Text(brand.ar)),
                        onTap: () => onSelected(option),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
