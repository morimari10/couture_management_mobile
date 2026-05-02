import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/material_item.dart';
import '../services/s3_service.dart';
import '../theme/app_theme.dart';

class MaterialsScreen extends StatefulWidget {
  const MaterialsScreen({super.key});

  @override
  State<MaterialsScreen> createState() => _MaterialsScreenState();
}

class _MaterialsScreenState extends State<MaterialsScreen> {
  List<MaterialItem> _materials = [];
  String _search = '';
  bool _loading = true;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await S3Service().loadData('couture_materials');
    if (!mounted) return;
    setState(() {
      _materials = data.map((e) => MaterialItem.fromJson(e as Map<String, dynamic>)).toList();
      _loading = false;
    });
  }

  Future<void> _save(List<MaterialItem> items) async {
    await S3Service().saveData('couture_materials', items.map((m) => m.toJson()).toList());
  }

  List<MaterialItem> get _filtered {
    if (_search.trim().isEmpty) return _materials;
    final q = _search.toLowerCase();
    return _materials.where((m) =>
        m.name.toLowerCase().contains(q) ||
        m.category.toLowerCase().contains(q) ||
        m.color.toLowerCase().contains(q) ||
        m.supplier.toLowerCase().contains(q)).toList();
  }

  void _openForm({MaterialItem? editing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _MaterialForm(
        editing: editing,
        onSave: (item) {
          setState(() {
            if (editing != null) {
              final idx = _materials.indexWhere((m) => m.id == editing.id);
              if (idx >= 0) _materials[idx] = item;
            } else {
              _materials.insert(0, item);
            }
          });
          _save(_materials);
        },
      ),
    );
  }

  Future<void> _delete(MaterialItem mat) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer ?'),
        content: Text('Supprimer "${mat.name}" ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _materials.removeWhere((m) => m.id == mat.id));
    await _save(_materials);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Scaffold(
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Rechercher par nom, catégorie...',
                prefixIcon: const Icon(Icons.search, color: AppTheme.textLight),
                suffixIcon: _search.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _search = '');
                        },
                      )
                    : null,
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          // List
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
                : filtered.isEmpty
                    ? _emptyState()
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: AppTheme.accent,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: filtered.length,
                          itemBuilder: (_, i) => _matCard(filtered[i]),
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter'),
      ),
    );
  }

  Widget _matCard(MaterialItem mat) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      mat.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: AppTheme.primaryDark,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryFaded,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      mat.category,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${mat.price.toStringAsFixed(2)} €   ${mat.unitLabel}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primary,
                ),
              ),
              if (mat.color.isNotEmpty || mat.supplier.isNotEmpty) ...[
                const SizedBox(height: 4),
                Wrap(
                  spacing: 12,
                  children: [
                    if (mat.color.isNotEmpty)
                      Text('🎨 ${mat.color}', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                    if (mat.supplier.isNotEmpty)
                      Text('🏪 ${mat.supplier}', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                  ],
                ),
              ],
              if (mat.notes.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(mat.notes, style: const TextStyle(fontSize: 12, color: AppTheme.textLight, fontStyle: FontStyle.italic)),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _openForm(editing: mat),
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Modifier'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primary,
                        side: const BorderSide(color: AppTheme.borderLight),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _delete(mat),
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: const Text('Supprimer'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.danger,
                        side: const BorderSide(color: Color(0xFFFDE8E8)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

  Widget _emptyState() => ListView(
        children: const [
          SizedBox(height: 80),
          Icon(Icons.web_asset_off, size: 72, color: AppTheme.borderLight),
          SizedBox(height: 16),
          Text(
            'Aucune matière première',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
          ),
          SizedBox(height: 8),
          Text(
            'Ajoutez vos tissus, fils, boutons...',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppTheme.textLight),
          ),
        ],
      );
}

// ─── Form bottom sheet ───

class _MaterialForm extends StatefulWidget {
  final MaterialItem? editing;
  final void Function(MaterialItem) onSave;

  const _MaterialForm({this.editing, required this.onSave});

  @override
  State<_MaterialForm> createState() => _MaterialFormState();
}

class _MaterialFormState extends State<_MaterialForm> {
  final _formKey = GlobalKey<FormState>();
  late String _name, _category, _unitType, _color, _supplier, _notes;
  late String _price;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    _name = e?.name ?? '';
    _category = e?.category ?? '';
    _unitType = e?.unitType ?? 'metre';
    _price = e != null ? e.price.toString() : '';
    _color = e?.color ?? '';
    _supplier = e?.supplier ?? '';
    _notes = e?.notes ?? '';
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    final now = DateTime.now();
    final item = MaterialItem(
      id: widget.editing?.id ?? const Uuid().v4(),
      name: _name.trim(),
      category: _category,
      unitType: _unitType,
      price: double.tryParse(_price) ?? 0,
      color: _color.trim(),
      supplier: _supplier.trim(),
      notes: _notes.trim(),
      createdAt: widget.editing?.createdAt ?? now,
      updatedAt: now,
    );
    widget.onSave(item);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.editing != null;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20, right: 20, top: 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isEdit ? 'Modifier la matière' : 'Nouvelle matière première',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primaryDark,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                initialValue: _name,
                decoration: const InputDecoration(labelText: 'Nom *'),
                validator: (v) => v == null || v.trim().isEmpty ? 'Requis' : null,
                onSaved: (v) => _name = v ?? '',
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _category.isEmpty ? null : _category,
                decoration: const InputDecoration(labelText: 'Catégorie *'),
                items: MaterialItem.categories
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() => _category = v ?? ''),
                validator: (v) => v == null || v.isEmpty ? 'Requis' : null,
                onSaved: (v) => _category = v ?? '',
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: _price,
                      decoration: const InputDecoration(labelText: 'Prix *', suffixText: '€'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Requis';
                        if (double.tryParse(v) == null) return 'Invalide';
                        return null;
                      },
                      onSaved: (v) => _price = v ?? '0',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _unitType,
                      decoration: const InputDecoration(labelText: 'Unité'),
                      items: MaterialItem.unitLabels.entries
                          .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 13))))
                          .toList(),
                      onChanged: (v) => setState(() => _unitType = v ?? 'metre'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: _color,
                decoration: const InputDecoration(labelText: 'Couleur', prefixText: '🎨 '),
                onSaved: (v) => _color = v ?? '',
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: _supplier,
                decoration: const InputDecoration(labelText: 'Fournisseur', prefixText: '🏪 '),
                onSaved: (v) => _supplier = v ?? '',
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: _notes,
                decoration: const InputDecoration(labelText: 'Notes'),
                maxLines: 2,
                onSaved: (v) => _notes = v ?? '',
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Annuler'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _submit,
                      child: Text(isEdit ? 'Modifier' : 'Ajouter'),
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
