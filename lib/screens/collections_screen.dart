import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/collection_model.dart';
import '../models/product_model.dart';
import '../services/s3_service.dart';
import '../theme/app_theme.dart';

class CollectionsScreen extends StatefulWidget {
  const CollectionsScreen({super.key});

  @override
  State<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends State<CollectionsScreen> {
  List<CollectionModel> _collections = [];
  List<ProductModel> _products = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final s3 = S3Service();
    final results = await Future.wait([
      s3.loadData('couture_collections'),
      s3.loadData('couture_products'),
    ]);
    if (!mounted) return;
    setState(() {
      _collections = results[0].map((e) => CollectionModel.fromJson(e as Map<String, dynamic>)).toList();
      _products = results[1].map((e) => ProductModel.fromJson(e as Map<String, dynamic>)).toList();
      _loading = false;
    });
  }

  Future<void> _save() async {
    await S3Service().saveData(
      'couture_collections',
      _collections.map((c) => c.toJson()).toList(),
    );
  }

  int _productCount(String collectionId) =>
      _products.where((p) => p.collectionId == collectionId).length;

  void _openForm({CollectionModel? editing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CollectionForm(
        editing: editing,
        onSave: (col) {
          setState(() {
            if (editing != null) {
              final idx = _collections.indexWhere((c) => c.id == editing.id);
              if (idx >= 0) _collections[idx] = col;
            } else {
              _collections.insert(0, col);
            }
          });
          _save();
        },
      ),
    );
  }

  Future<void> _delete(CollectionModel col) async {
    final count = _productCount(col.id);
    final msg = count > 0
        ? 'Supprimer "${col.name}" ? Les $count produits associés perdront leur collection.'
        : 'Supprimer "${col.name}" ?';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer ?'),
        content: Text(msg),
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
    setState(() => _collections.removeWhere((c) => c.id == col.id));
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : _collections.isEmpty
              ? _emptyState()
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppTheme.accent,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _collections.length,
                    itemBuilder: (_, i) => _collectionCard(_collections[i]),
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle collection'),
      ),
    );
  }

  Widget _collectionCard(CollectionModel col) {
    final count = _productCount(col.id);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(col.emoji, style: const TextStyle(fontSize: 32)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        col.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: AppTheme.primaryDark,
                        ),
                      ),
                      if (col.description.isNotEmpty)
                        Text(
                          col.description,
                          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontStyle: FontStyle.italic),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryFaded,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$count produit${count != 1 ? 's' : ''}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openForm(editing: col),
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
                    onPressed: () => _delete(col),
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
  }

  Widget _emptyState() => ListView(
        children: const [
          SizedBox(height: 80),
          Icon(Icons.folder_off_outlined, size: 72, color: AppTheme.borderLight),
          SizedBox(height: 16),
          Text('Aucune collection', textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: AppTheme.textSecondary)),
          SizedBox(height: 8),
          Text('Organisez vos produits par collection.', textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppTheme.textLight)),
        ],
      );
}

// ─── Form ───

class _CollectionForm extends StatefulWidget {
  final CollectionModel? editing;
  final void Function(CollectionModel) onSave;
  const _CollectionForm({this.editing, required this.onSave});

  @override
  State<_CollectionForm> createState() => _CollectionFormState();
}

class _CollectionFormState extends State<_CollectionForm> {
  final _formKey = GlobalKey<FormState>();
  late String _name, _emoji, _description;

  @override
  void initState() {
    super.initState();
    _name = widget.editing?.name ?? '';
    _emoji = widget.editing?.emoji ?? '🧵';
    _description = widget.editing?.description ?? '';
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    final now = DateTime.now();
    widget.onSave(CollectionModel(
      id: widget.editing?.id ?? const Uuid().v4(),
      name: _name.trim(),
      emoji: _emoji,
      description: _description.trim(),
      createdAt: widget.editing?.createdAt ?? now,
      updatedAt: now,
    ));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20, right: 20, top: 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.editing != null ? 'Modifier la collection' : 'Nouvelle collection',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.primaryDark),
              ),
              const SizedBox(height: 16),
              // Emoji picker
              const Text('Emoji', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: CollectionModel.emojis.map((e) {
                  final active = _emoji == e;
                  return GestureDetector(
                    onTap: () => setState(() => _emoji = e),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: active ? AppTheme.primary : AppTheme.borderLight,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        color: active ? AppTheme.primaryFaded : Colors.white,
                      ),
                      child: Center(child: Text(e, style: const TextStyle(fontSize: 22))),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              TextFormField(
                initialValue: _name,
                decoration: const InputDecoration(labelText: 'Nom *'),
                validator: (v) => v == null || v.trim().isEmpty ? 'Requis' : null,
                onSaved: (v) => _name = v ?? '',
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: _description,
                decoration: const InputDecoration(labelText: 'Description'),
                maxLines: 2,
                onSaved: (v) => _description = v ?? '',
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler'))),
                  const SizedBox(width: 12),
                  Expanded(child: ElevatedButton(onPressed: _submit, child: Text(widget.editing != null ? 'Modifier' : 'Créer'))),
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
