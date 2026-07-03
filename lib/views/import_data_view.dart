import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';

import '../i18n/translator.dart';
import '../providers/theme_provider.dart';
import '../components/theme/paedra_colors.dart';
import '../database/database_manager.dart';
import '../models/account.dart';
import '../services/import_service.dart';

class ImportDataView extends StatefulWidget {
  const ImportDataView({super.key});

  @override
  State<ImportDataView> createState() => _ImportDataViewState();
}

class _ImportDataViewState extends State<ImportDataView> {
  final _db = DatabaseManager.instance;
  final _importService = ImportService();

  int _currentStep = 0;
  List<Account> _accounts = [];
  int? _selectedAccountId;
  String? _selectedDelimiter;
  ImportPreview? _preview;
  bool _loading = false;
  String? _error;
  ImportResult? _result;
  List<ImportMapping>? _userMappings;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    final accounts = await _db.getAllAccounts();
    setState(() {
      _accounts = accounts;
      if (accounts.isNotEmpty) _selectedAccountId = accounts.first.id;
    });
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'txt'],
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return;

      setState(() {
        _loading = true;
        _error = null;
      });

      final file = result.files.first;
      final path = file.path;
      if (path == null) {
        setState(() {
          _loading = false;
          _error = Translator.t('import_file_not_found');
        });
        return;
      }

      final preview = await _importService.previewCsv(path, delimiter: _selectedDelimiter);

      if (preview.alreadyImported && mounted) {
        final proceed = await _showDuplicateWarning();
        if (!proceed) {
          setState(() {
            _loading = false;
          });
          return;
        }
      }

      setState(() {
        _preview = preview;
        _userMappings = List.from(preview.suggestedMappings);
        _loading = false;
        _currentStep = 1;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<bool> _showDuplicateWarning() async {
    final themeName = context.read<ThemeProvider>().themeName;
    final colors = PeadraTheme.getColors(themeName);

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        title: Row(
          children: [
            Icon(Icons.warning_amber, color: colors.warning),
            const SizedBox(width: 8),
            Expanded(
              child: Text(Translator.t('import_duplicate_warning'),
                  style: TextStyle(color: colors.text, fontSize: 16)),
            ),
          ],
        ),
        content: Text(Translator.t('import_duplicate_content'),
            style: TextStyle(color: colors.text)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(Translator.t('btn_cancel'),
                style: TextStyle(color: colors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: colors.warning),
            child: Text(Translator.t('import_anyway'),
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  void _updateMapping(int columnIndex, ColumnMapping newMapping) {
    if (_userMappings == null) return;
    setState(() {
      _userMappings = _userMappings!.map((m) {
        if (m.columnIndex == columnIndex) {
          return ImportMapping(columnIndex, newMapping);
        }
        return m;
      }).toList();
    });
  }

  Future<void> _repickFile() async {
    if (_preview?.filePath == null) return;
    try {
      setState(() => _loading = true);
      final preview = await _importService.previewCsv(_preview!.filePath!, delimiter: _selectedDelimiter);
      setState(() {
        _preview = preview;
        _userMappings = List.from(preview.suggestedMappings);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _import() async {
    if (_preview == null || _selectedAccountId == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final account = _accounts.firstWhere((a) => a.id == _selectedAccountId);
      final result = await _importService.importCsv(
        filePath: _preview!.filePath!,
        mappings: _userMappings ?? _preview!.suggestedMappings,
        transactionType: 'expense',
        accountId: _selectedAccountId!,
        currency: account.currency,
        delimiter: _selectedDelimiter,
      );

      setState(() {
        _result = result;
        _loading = false;
        _currentStep = 2;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeName = context.watch<ThemeProvider>().themeName;
    final colors = PeadraTheme.getColors(themeName);

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        title: Text(Translator.t('import_title'),
            style: TextStyle(color: colors.text)),
        backgroundColor: colors.surface,
        iconTheme: IconThemeData(color: colors.text),
        actions: [
          if (_currentStep < 2)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(Translator.t('btn_cancel'),
                  style: TextStyle(color: colors.textSecondary)),
            ),
        ],
      ),
      body: Column(
        children: [
          // Stepper header
          _buildStepperHeader(colors),
          Divider(height: 1, color: colors.borderColor),
          // Content
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator(color: colors.accent))
                : _error != null
                    ? _buildError(colors)
                    : _buildStepContent(colors),
          ),
          // Bottom actions
          _buildActions(colors),
        ],
      ),
    );
  }

  Widget _buildStepperHeader(PeadraColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      color: colors.surface,
      child: Row(
        children: [
          _stepIndicator(0, Translator.t('import_step_file'), colors),
          _stepConnector(0, colors),
          _stepIndicator(1, Translator.t('import_step_configure'), colors),
          _stepConnector(1, colors),
          _stepIndicator(2, Translator.t('import_step_result'), colors),
        ],
      ),
    );
  }

  Widget _stepIndicator(int step, String label, PeadraColors colors) {
    final isActive = _currentStep == step;
    final isDone = _currentStep > step;
    return Column(
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: isDone
              ? colors.incomeIcon
              : isActive
                  ? colors.accent
                  : colors.borderColor,
          child: isDone
              ? const Icon(Icons.check, size: 16, color: Colors.white)
              : Text(
                  '${step + 1}',
                  style: TextStyle(
                    color: isActive ? Colors.white : colors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isActive ? colors.text : colors.textSecondary,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _stepConnector(int afterStep, PeadraColors colors) {
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        color: _currentStep > afterStep ? colors.incomeIcon : colors.borderColor,
      ),
    );
  }

  Widget _buildError(PeadraColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: colors.expenseIcon),
            const SizedBox(height: 12),
            Text(
              _error ?? Translator.t('import_unknown_error'),
              style: TextStyle(color: colors.text),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepContent(PeadraColors colors) {
    switch (_currentStep) {
      case 0:
        return _buildFileStep(colors);
      case 1:
        return _buildConfigStep(colors);
      case 2:
        return _buildResultStep(colors);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildFileStep(PeadraColors colors) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.upload_file, size: 64, color: colors.accent),
          const SizedBox(height: 16),
          Text(
            Translator.t('import_select_file'),
            style: TextStyle(fontSize: 18, color: colors.text),
          ),
          const SizedBox(height: 8),
          Text(
            Translator.t('import_csv_hint'),
            style: TextStyle(color: colors.textSecondary),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _pickFile,
            icon: const Icon(Icons.folder_open, color: Colors.white),
            label: Text(Translator.t('import_browse'),
                style: const TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(backgroundColor: colors.accent),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigStep(PeadraColors colors) {
    if (_preview == null) return const SizedBox.shrink();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Separator dropdown
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedDelimiter,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: Translator.t('import_separator'),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    filled: true,
                    fillColor: colors.bg,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  items: [
                    DropdownMenuItem(value: null, child: Text(Translator.t('import_separator_auto'))),
                    DropdownMenuItem(value: ',', child: Text(Translator.t('import_separator_comma'))),
                    DropdownMenuItem(value: ';', child: Text(Translator.t('import_separator_semicolon'))),
                    DropdownMenuItem(value: '\t', child: Text(Translator.t('import_separator_tab'))),
                    DropdownMenuItem(value: '|', child: Text(Translator.t('import_separator_pipe'))),
                  ],
                  onChanged: (v) {
                    setState(() => _selectedDelimiter = v);
                    _repickFile();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Account dropdown
          DropdownButtonFormField<int>(
            initialValue: _selectedAccountId,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: Translator.t('trans_account'),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              filled: true,
              fillColor: colors.bg,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            items: _accounts
                .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
                .toList(),
            onChanged: (v) => setState(() => _selectedAccountId = v),
          ),
          const SizedBox(height: 16),

          // Column mapping
          Text(
            Translator.t('import_column_mapping'),
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.text),
          ),
          const SizedBox(height: 4),
          Text(
            Translator.t('import_mapping_hint'),
            style: TextStyle(fontSize: 11, color: colors.textSecondary),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: colors.borderColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                // Header row
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: colors.bg,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(8),
                      topRight: Radius.circular(8),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(Translator.t('import_col_header'),
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: colors.textSecondary)),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(Translator.t('import_mapping_target'),
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: colors.textSecondary)),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: colors.borderColor),
                // Column rows
                for (int i = 0; i < _preview!.headers.length; i++) ...[
                  _buildColumnMappingRow(i, colors),
                  if (i < _preview!.headers.length - 1) Divider(height: 1, color: colors.borderColor),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Preview table
          Text(
            Translator.t('import_preview'),
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.text),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: colors.borderColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: _preview!.headers
                    .map((h) => DataColumn(
                        label: Text(h,
                            style: TextStyle(
                                fontSize: 11, color: colors.textSecondary, fontWeight: FontWeight.w500))))
                    .toList(),
                rows: _preview!.rows
                    .map((row) => DataRow(
                          cells: row
                              .map((cell) => DataCell(Text(cell,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: colors.text))))
                              .toList(),
                        ))
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColumnMappingRow(int columnIndex, PeadraColors colors) {
    final header = _preview!.headers[columnIndex];
    final currentMapping = _userMappings
        ?.firstWhere((m) => m.columnIndex == columnIndex,
            orElse: () => ImportMapping(columnIndex, ColumnMapping.unused))
        .mapping ?? ColumnMapping.unused;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(header,
                style: TextStyle(fontSize: 12, color: colors.text),
                overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<ColumnMapping>(
              initialValue: currentMapping,
              isExpanded: true,
              isDense: true,
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                filled: true,
                fillColor: colors.surface,
                isCollapsed: true,
              ),
              items: [
                DropdownMenuItem(value: ColumnMapping.date, child: Text(Translator.t('import_date'))),
                DropdownMenuItem(value: ColumnMapping.description, child: Text(Translator.t('import_description'))),
                DropdownMenuItem(value: ColumnMapping.amount, child: Text(Translator.t('import_amount'))),
                DropdownMenuItem(value: ColumnMapping.credit, child: Text(Translator.t('import_credit'))),
                DropdownMenuItem(value: ColumnMapping.debit, child: Text(Translator.t('import_debit'))),
                DropdownMenuItem(value: ColumnMapping.type, child: Text(Translator.t('import_type'))),
                DropdownMenuItem(value: ColumnMapping.unused, child: Text(Translator.t('import_unused'))),
              ],
              onChanged: (v) {
                if (v != null) _updateMapping(columnIndex, v);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultStep(PeadraColors colors) {
    if (_result == null) return const SizedBox.shrink();

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 64, color: colors.incomeIcon),
            const SizedBox(height: 16),
            Text(
              Translator.t('import_complete'),
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: colors.text),
            ),
            const SizedBox(height: 16),
            _resultStat(Translator.t('import_total'), _result!.totalRows, colors),
            _resultStat(Translator.t('import_imported'), _result!.imported, colors, color: colors.incomeIcon),
            _resultStat(Translator.t('import_skipped'), _result!.skipped, colors, color: colors.expenseIcon),
            _resultStat(Translator.t('import_duplicates'), _result!.duplicates, colors, color: Colors.orange),
            if (_result!.errors.isNotEmpty) ...[
              const SizedBox(height: 12),
              ExpansionTile(
                title: Text(
                  '${Translator.t('import_errors')} (${_result!.errors.length})',
                  style: TextStyle(color: colors.expenseIcon, fontSize: 13),
                ),
                children: _result!.errors
                    .take(20)
                    .map((e) => Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          child: Text(e,
                              style: TextStyle(
                                  fontSize: 11, color: colors.textSecondary)),
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _resultStat(String label, int value, PeadraColors colors,
      {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('$label: ', style: TextStyle(color: colors.textSecondary)),
          Text(
            value.toString(),
            style: TextStyle(
              color: color ?? colors.text,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(PeadraColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.borderColor)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (_currentStep == 0) ...[
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(Translator.t('btn_cancel'),
                  style: TextStyle(color: colors.textSecondary)),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.folder_open, color: Colors.white, size: 16),
              label: Text(Translator.t('import_browse'),
                  style: const TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(backgroundColor: colors.accent),
            ),
          ],
          if (_currentStep == 1) ...[
            TextButton(
              onPressed: () => setState(() {
                _currentStep = 0;
                _preview = null;
                _userMappings = null;
              }),
              child: Text(Translator.t('btn_back'),
                  style: TextStyle(color: colors.textSecondary)),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(Translator.t('btn_cancel'),
                  style: TextStyle(color: colors.textSecondary)),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _import,
              style: ElevatedButton.styleFrom(backgroundColor: colors.accent),
              child: Text(Translator.t('import_btn_import'),
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
          if (_currentStep == 2)
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(backgroundColor: colors.accent),
              child: Text(Translator.t('btn_close'),
                  style: const TextStyle(color: Colors.white)),
            ),
        ],
      ),
    );
  }
}
