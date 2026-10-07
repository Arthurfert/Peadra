import 'package:flutter/material.dart';

import '../../../../core/i18n/translator.dart';
import '../../../../core/theme/peadra_colors.dart';

/// Custom date-range picker used for the dashboard custom period.
///
/// Flutter's built-in [showDateRangePicker] cannot be customized from the
/// outside (no way to inject extra actions, and its desktop input mode lays
/// out the title in a left column). This dialog keeps the same layout on
/// every platform: title on top, manual entry fields plus calendar buttons,
/// and a shortcut that sets the start to the first recorded transaction.
class CustomRangeDialog extends StatefulWidget {
  final DateTime initialStart;
  final DateTime initialEnd;
  final DateTime lastDate;
  final String? firstTransactionDate;
  final PeadraColors colors;

  const CustomRangeDialog({
    super.key,
    required this.initialStart,
    required this.initialEnd,
    required this.lastDate,
    required this.colors,
    this.firstTransactionDate,
  });

  @override
  State<CustomRangeDialog> createState() => _CustomRangeDialogState();
}

class _CustomRangeDialogState extends State<CustomRangeDialog> {
  late final TextEditingController _startCtrl;
  late final TextEditingController _endCtrl;
  String? _error;

  static String _fmt(DateTime d) => d.toIso8601String().substring(0, 10);

  @override
  void initState() {
    super.initState();
    _startCtrl = TextEditingController(text: _fmt(widget.initialStart));
    _endCtrl = TextEditingController(text: _fmt(widget.initialEnd));
  }

  @override
  void dispose() {
    _startCtrl.dispose();
    _endCtrl.dispose();
    super.dispose();
  }

  DateTime? get _parsedStart => DateTime.tryParse(_startCtrl.text.trim());
  DateTime? get _parsedEnd => DateTime.tryParse(_endCtrl.text.trim());

  Future<void> _pickStart() async {
    final end = _parsedEnd;
    final last = (end != null && end.isBefore(widget.lastDate)) ? end : widget.lastDate;
    var initial = _parsedStart ?? widget.initialStart;
    if (initial.isAfter(last)) initial = last;
    if (initial.isBefore(DateTime(2000))) initial = DateTime(2000);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: last,
    );
    if (picked == null) return;
    setState(() {
      _startCtrl.text = _fmt(picked);
      _error = null;
    });
  }

  Future<void> _pickEnd() async {
    var first = _parsedStart ?? widget.initialStart;
    if (first.isAfter(widget.lastDate)) first = widget.lastDate;
    var initial = _parsedEnd ?? widget.initialEnd;
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(widget.lastDate)) initial = widget.lastDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: widget.lastDate,
    );
    if (picked == null) return;
    setState(() {
      _endCtrl.text = _fmt(picked);
      _error = null;
    });
  }

  void _fromStart() {
    final first = widget.firstTransactionDate;
    if (first == null) return;
    setState(() {
      _startCtrl.text = first;
      _error = null;
    });
  }

  void _submit() {
    final start = _parsedStart;
    final end = _parsedEnd;
    if (start == null || end == null) {
      setState(() => _error = Translator.t('period_invalid_range'));
      return;
    }
    final startDate = DateTime(start.year, start.month, start.day);
    final endDate = DateTime(end.year, end.month, end.day);
    if (startDate.isAfter(endDate) || endDate.isAfter(widget.lastDate)) {
      setState(() => _error = Translator.t('period_invalid_range'));
      return;
    }
    Navigator.pop(context, DateTimeRange(start: startDate, end: endDate));
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return AlertDialog(
      backgroundColor: colors.surface,
      title: Text(Translator.t('period_custom_title'),
          style: TextStyle(color: colors.text)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(Translator.t('period_start'),
                style: TextStyle(color: colors.textSecondary, fontSize: 12)),
            const SizedBox(height: 6),
            Row(
              children: [
                IconButton(
                  icon: Icon(Icons.calendar_month, color: colors.accent),
                  tooltip: Translator.t('period_start'),
                  onPressed: _pickStart,
                ),
                Expanded(
                  child: TextField(
                    controller: _startCtrl,
                    keyboardType: TextInputType.datetime,
                    onChanged: (_) {
                      if (_error != null) setState(() => _error = null);
                    },
                    decoration: InputDecoration(
                      hintText: 'YYYY-MM-DD',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ),
            if (widget.firstTransactionDate != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _fromStart,
                  label: Text(Translator.t('period_from_first'),
                      style: TextStyle(color: colors.accent)),
                ),
              ),
            const SizedBox(height: 12),
            Text(Translator.t('period_end'),
                style: TextStyle(color: colors.textSecondary, fontSize: 12)),
            const SizedBox(height: 6),
            Row(
              children: [
                IconButton(
                  icon: Icon(Icons.calendar_month, color: colors.accent),
                  tooltip: Translator.t('period_end'),
                  onPressed: _pickEnd,
                ),
                Expanded(
                  child: TextField(
                    controller: _endCtrl,
                    keyboardType: TextInputType.datetime,
                    onChanged: (_) {
                      if (_error != null) setState(() => _error = null);
                    },
                    decoration: InputDecoration(
                      hintText: 'YYYY-MM-DD',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!,
                    style:
                        TextStyle(color: colors.error, fontSize: 12)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(Translator.t('btn_cancel')),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(backgroundColor: colors.accent),
          child: Text(Translator.t('btn_save'),
              style: const TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
