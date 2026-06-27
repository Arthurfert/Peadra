import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';

import '../i18n/translator.dart';
import '../providers/theme_provider.dart';
import '../components/theme/paedra_colors.dart';
import '../database/database_manager.dart';
import '../models/account.dart';
import '../services/import_service.dart';
import '../responsive/responsive_layout.dart';

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
  String _transactionType = 'expense';
  ImportPreview? _preview;
  bool _loading = false;
  String? _error;
  ImportResult? _result;
  List<PlatformFile>? _pickedFiles;

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
          _error = 'File not found';
        });
        return;
      }

      final preview = await _importService.previewCsv(path);
      setState(() {
        _preview = preview;
        _pickedFiles = result.files;
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
        mappings: _preview!.suggestedMappings,
        transactionType: _transactionType,
        accountId: _selectedAccountId!,
        currency: account.currency,
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
    final isPhone = ResponsiveLayout.isPhone(context);

    final content = Scaffold(
      backgroundColor: colors.bg,
      appBar: isPhone
          ? AppBar(
              title: Text(Translator.t('import_title'),
                  style: TextStyle(color: colors.text)),
              backgroundColor: colors.surface,
              iconTheme: IconThemeData(color: colors.text),
            )
          : null,
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

    if (isPhone) return content;

    // Desktop: show as dialog
    return Dialog(
      backgroundColor: colors.surface,
      child: SizedBox(
        width: 640,
        height: 480,
        child: content,
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
              _error ?? 'Unknown error',
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            Translator.t('import_configure'),
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colors.text),
          ),
          const SizedBox(height: 16),

          // Preview table
          if (_preview != null) ...[
            Text(
              Translator.t('import_preview'),
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: colors.textSecondary),
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
                                  fontSize: 12, color: colors.text))))
                      .toList(),
                  rows: _preview!.rows
                      .map((row) => DataRow(
                            cells: row
                                .map((cell) => DataCell(Text(cell,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: colors.textSecondary))))
                                .toList(),
                          ))
                      .toList(),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Transaction type
          DropdownButtonFormField<String>(
            initialValue: _transactionType,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: Translator.t('import_transaction_type'),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              filled: true,
              fillColor: colors.bg,
            ),
            items: [
              DropdownMenuItem(value: 'expense', child: Text(Translator.t('trans_expense'))),
              DropdownMenuItem(value: 'income', child: Text(Translator.t('trans_income'))),
            ],
            onChanged: (v) => setState(() => _transactionType = v ?? 'expense'),
          ),
          const SizedBox(height: 12),

          // Account
          DropdownButtonFormField<int>(
            initialValue: _selectedAccountId,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: Translator.t('trans_account'),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              filled: true,
              fillColor: colors.bg,
            ),
            items: _accounts
                .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
                .toList(),
            onChanged: (v) => setState(() => _selectedAccountId = v),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.borderColor)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (_currentStep > 0 && _currentStep < 2) ...[
            TextButton(
              onPressed: () => setState(() => _currentStep--),
              child: Text(Translator.t('btn_back')),
            ),
            const SizedBox(width: 8),
          ],
          if (_currentStep == 0)
            ElevatedButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.folder_open, color: Colors.white),
              label: Text(Translator.t('import_browse'),
                  style: const TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(backgroundColor: colors.accent),
            ),
          if (_currentStep == 1) ...[
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(Translator.t('btn_cancel')),
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
