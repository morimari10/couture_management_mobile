import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import '../models/account_model.dart';
import '../services/finance_report_service.dart';
import '../services/s3_service.dart';
import '../theme/app_theme.dart';

const _storageKey = 'couture_accounts';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> with SingleTickerProviderStateMixin {
  List<AccountEntry> _entries = [];
  late TabController _tabController;
  bool _loading = true;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await S3Service().loadData(_storageKey);
    if (!mounted) return;
    setState(() {
      _entries = data.map((e) => AccountEntry.fromJson(e as Map<String, dynamic>)).toList();
      _loading = false;
    });
  }

  Future<void> _save() async {
    await S3Service().saveData(_storageKey, _entries.map((e) => e.toJson()).toList());
  }

  List<AccountEntry> get _ins => _entries.where((e) => e.isIn).toList();
  List<AccountEntry> get _outs => _entries.where((e) => !e.isIn).toList();
  double _sum(Iterable<AccountEntry> list) => list.fold(0, (s, e) => s + e.amount);

  void _openForm({AccountEntry? editing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _EntryForm(
        editing: editing,
        initialType: _tabController.index == 0 ? AccountEntry.typeIn : AccountEntry.typeOut,
        onSave: (entry) {
          setState(() {
            final idx = _entries.indexWhere((e) => e.id == entry.id);
            if (idx >= 0) {
              _entries[idx] = entry;
            } else {
              _entries.insert(0, entry);
            }
            _entries.sort((a, b) => b.date.compareTo(a.date));
          });
          _save();
        },
      ),
    );
  }

  Future<void> _delete(AccountEntry entry) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Confirmer'),
            content: Text('Supprimer cette ${entry.isIn ? 'entrée' : 'sortie'} ?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Supprimer', style: TextStyle(color: AppTheme.danger)),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    setState(() => _entries.removeWhere((e) => e.id == entry.id));
    await _save();
  }

  Future<void> _openExportPicker() async {
    final months = FinanceReportService.availableAccountMonths(_entries);
    final month = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text('Relevé mensuel PDF',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.primaryDark)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: months
                    .map((m) => ListTile(
                          leading: const Icon(Icons.picture_as_pdf_outlined, color: AppTheme.primary),
                          title: Text(FinanceReportService.monthLabel(m)),
                          onTap: () => Navigator.pop(ctx, m),
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
    if (month == null || !mounted) return;
    setState(() => _exporting = true);
    try {
      await FinanceReportService.shareAccountsReport(month: month, entries: _entries);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export PDF impossible : $e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _viewDocument(String key) async {
    final uri = Uri.parse(S3Service().getPresignedUrl(key));
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Impossible d'ouvrir le justificatif")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ins = _ins;
    final outs = _outs;
    final balance = _sum(ins) - _sum(outs);
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : Column(
              children: [
                Container(
                  color: AppTheme.primaryFaded,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      _sumCard('Entrées', _sum(ins), AppTheme.success),
                      _vDivider(),
                      _sumCard('Sorties', _sum(outs), AppTheme.danger),
                      _vDivider(),
                      _sumCard('Solde', balance, balance >= 0 ? AppTheme.success : AppTheme.danger),
                      _vDivider(),
                      IconButton(
                        tooltip: 'Relevé mensuel PDF',
                        onPressed: _exporting ? null : _openExportPicker,
                        icon: _exporting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent),
                              )
                            : const Icon(Icons.picture_as_pdf_outlined, color: AppTheme.primary),
                      ),
                    ],
                  ),
                ),
                TabBar(
                  controller: _tabController,
                  labelColor: AppTheme.primary,
                  unselectedLabelColor: AppTheme.textSecondary,
                  indicatorColor: AppTheme.primary,
                  tabs: [
                    Tab(text: 'Entrées (${ins.length})'),
                    Tab(text: 'Sorties (${outs.length})'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _list(ins, 'Aucune entrée', 'Enregistrez l\'argent qui rentre'),
                      _list(outs, 'Aucune sortie', 'Enregistrez l\'argent qui sort'),
                    ],
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: AnimatedBuilder(
          animation: _tabController,
          builder: (_, __) => Text(_tabController.index == 0 ? 'Entrée' : 'Sortie'),
        ),
      ),
    );
  }

  Widget _list(List<AccountEntry> list, String emptyTitle, String emptySub) => RefreshIndicator(
        onRefresh: _load,
        color: AppTheme.accent,
        child: list.isEmpty
            ? _emptyState(emptyTitle, emptySub)
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                itemCount: list.length,
                itemBuilder: (_, i) => _entryCard(list[i]),
              ),
      );

  Widget _sumCard(String label, double value, Color color) => Expanded(
        child: Column(
          children: [
            Text(
              '${value.toStringAsFixed(2)} €',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: color),
            ),
            Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
          ],
        ),
      );

  Widget _vDivider() => Container(width: 1, height: 32, color: AppTheme.borderLight);

  Widget _entryCard(AccountEntry e) {
    final color = e.isIn ? AppTheme.success : AppTheme.danger;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.label,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.primaryDark)),
                      if (e.party.isNotEmpty)
                        Text(e.party, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                      if (e.notes.isNotEmpty)
                        Text(e.notes, style: const TextStyle(fontSize: 11, color: AppTheme.textLight, fontStyle: FontStyle.italic)),
                      Text(_fmtDate(e.date), style: const TextStyle(fontSize: 11, color: AppTheme.textLight)),
                    ],
                  ),
                ),
                Text(
                  '${e.isIn ? '+' : '-'}${e.amount.toStringAsFixed(2)} €',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: color),
                ),
              ],
            ),
            Row(
              children: [
                if (e.invoiceKey.isNotEmpty)
                  GestureDetector(
                    onTap: () => _viewDocument(e.invoiceKey),
                    child: Container(
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F4FD),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.receipt_outlined, size: 14, color: Color(0xFF2980B9)),
                          const SizedBox(width: 4),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 160),
                            child: Text(
                              e.invoiceName.isNotEmpty ? e.invoiceName : 'Justificatif',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11, color: Color(0xFF2980B9), fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18, color: AppTheme.primary),
                  onPressed: () => _openForm(editing: e),
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18, color: AppTheme.danger),
                  onPressed: () => _delete(e),
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _fmtDate(String dateStr) {
    final d = DateTime.tryParse(dateStr);
    if (d == null) return dateStr;
    return DateFormat('d MMM yyyy', 'fr_FR').format(d);
  }

  Widget _emptyState(String title, String subtitle) => ListView(
        children: [
          const SizedBox(height: 80),
          const Icon(Icons.account_balance_wallet_outlined, size: 72, color: AppTheme.borderLight),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: AppTheme.textSecondary)),
          const SizedBox(height: 8),
          Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: AppTheme.textLight)),
        ],
      );
}

// ─── Entry Form ───

class _EntryForm extends StatefulWidget {
  final AccountEntry? editing;
  final String initialType;
  final void Function(AccountEntry) onSave;
  const _EntryForm({this.editing, required this.initialType, required this.onSave});

  @override
  State<_EntryForm> createState() => _EntryFormState();
}

class _EntryFormState extends State<_EntryForm> {
  final _formKey = GlobalKey<FormState>();
  late String _type, _date, _label, _party, _amount, _notes;
  PlatformFile? _file;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    _type = e?.type ?? widget.initialType;
    _date = e?.date ?? DateFormat('yyyy-MM-dd').format(DateTime.now());
    _label = e?.label ?? '';
    _party = e?.party ?? '';
    _amount = e != null ? e.amount.toString() : '';
    _notes = e?.notes ?? '';
  }

  bool get _isIn => _type == AccountEntry.typeIn;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_date) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) setState(() => _date = DateFormat('yyyy-MM-dd').format(picked));
  }

  Future<void> _pickFile() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg', 'webp'],
      withData: true,
    );
    if (res != null && res.files.isNotEmpty) setState(() => _file = res.files.first);
  }

  String _mimeType(String name) {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return 'application/pdf';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    final id = widget.editing?.id ?? const Uuid().v4();
    var invoiceKey = widget.editing?.invoiceKey ?? '';
    var invoiceName = widget.editing?.invoiceName ?? '';

    final file = _file;
    if (file != null && file.bytes != null) {
      setState(() => _uploading = true);
      try {
        final key = 'couture_accounts_docs/$id/${file.name}';
        await S3Service().uploadFile(key, file.bytes!, _mimeType(file.name));
        invoiceKey = key;
        invoiceName = file.name;
      } catch (e) {
        if (!mounted) return;
        setState(() => _uploading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload du justificatif échoué : $e')));
        return;
      }
    }

    final now = DateTime.now();
    widget.onSave(AccountEntry(
      id: id,
      type: _type,
      date: _date,
      label: _label.trim(),
      party: _party.trim(),
      amount: double.tryParse(_amount.replaceAll(',', '.')) ?? 0,
      notes: _notes.trim(),
      invoiceKey: invoiceKey,
      invoiceName: invoiceName,
      createdAt: widget.editing?.createdAt ?? now,
      updatedAt: now,
    ));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final currentDoc = _file?.name ?? (widget.editing?.invoiceName ?? '');
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.editing != null
                    ? (_isIn ? "Modifier l'entrée" : 'Modifier la sortie')
                    : (_isIn ? 'Nouvelle entrée' : 'Nouvelle sortie'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.primaryDark),
              ),
              const SizedBox(height: 16),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: AccountEntry.typeIn, label: Text('Entrée'), icon: Icon(Icons.arrow_upward)),
                  ButtonSegment(value: AccountEntry.typeOut, label: Text('Sortie'), icon: Icon(Icons.arrow_downward)),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() => _type = s.first),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: _pickDate,
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Date *', suffixIcon: Icon(Icons.calendar_today, size: 18)),
                  child: Text(_date),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: _label,
                decoration: InputDecoration(
                  labelText: 'Libellé *',
                  hintText: _isIn ? 'Ex : Vente robe, acompte...' : 'Ex : Tissu coton, emplacement marché...',
                ),
                validator: (v) => v == null || v.trim().isEmpty ? 'Requis' : null,
                onSaved: (v) => _label = v ?? '',
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: _party,
                decoration: InputDecoration(labelText: _isIn ? 'Provenance' : 'Bénéficiaire'),
                onSaved: (v) => _party = v ?? '',
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: _amount,
                decoration: const InputDecoration(labelText: 'Montant *', suffixText: '€'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) => v == null || double.tryParse(v.replaceAll(',', '.')) == null ? 'Montant invalide' : null,
                onSaved: (v) => _amount = v ?? '0',
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: _notes,
                decoration: const InputDecoration(labelText: 'Notes'),
                maxLines: 2,
                onSaved: (v) => _notes = v ?? '',
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _uploading ? null : _pickFile,
                icon: const Icon(Icons.attach_file, size: 18),
                label: Text(
                  currentDoc.isNotEmpty ? currentDoc : 'Ajouter un justificatif',
                  overflow: TextOverflow.ellipsis,
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  minimumSize: const Size(double.infinity, 44),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler'))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _uploading ? null : _submit,
                      child: _uploading
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(widget.editing != null ? 'Modifier' : 'Ajouter'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
