import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import '../models/calendar_event_model.dart';
import '../services/s3_service.dart';
import '../theme/app_theme.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  List<CalendarEvent> _events = [];
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime.now();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await S3Service().loadData('couture_marches');
    if (!mounted) return;
    setState(() {
      _events = data.map((e) => CalendarEvent.fromJson(e as Map<String, dynamic>)).toList();
      _loading = false;
    });
  }

  Future<void> _save() async {
    await S3Service().saveData('couture_marches', _events.map((e) => e.toJson()).toList());
  }

  List<CalendarEvent> _eventsForDay(DateTime day) {
    final dayStr = DateFormat('yyyy-MM-dd').format(day);
    return _events.where((e) {
      if (e.date == dayStr) return true;
      if (e.endDate.isNotEmpty) {
        final start = DateTime.tryParse(e.date);
        final end = DateTime.tryParse(e.endDate);
        if (start != null && end != null) {
          final d = DateTime(day.year, day.month, day.day);
          final s = DateTime(start.year, start.month, start.day);
          final en = DateTime(end.year, end.month, end.day);
          return !d.isBefore(s) && !d.isAfter(en);
        }
      }
      return false;
    }).toList();
  }

  void _openForm({CalendarEvent? editing, DateTime? defaultDate}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _EventForm(
        editing: editing,
        defaultDate: defaultDate,
        onSave: (ev) {
          setState(() {
            if (editing != null) {
              final idx = _events.indexWhere((e) => e.id == editing.id);
              if (idx >= 0) _events[idx] = ev;
            } else {
              _events.add(ev);
            }
          });
          _save();
        },
      ),
    );
  }

  Future<void> _delete(CalendarEvent ev) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer ?'),
        content: Text('Supprimer "${ev.name}" ?'),
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
    setState(() => _events.removeWhere((e) => e.id == ev.id));
    await _save();
  }

  // ── Bottom sheet: événements du jour ──
  void _showDaySheet(DateTime day) {
    final events = _eventsForDay(day);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.72),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Poignée
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 6),
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: AppTheme.borderLight, borderRadius: BorderRadius.circular(2)),
            ),
            // En-tête
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 16, 12),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _capitalize(DateFormat('EEEE', 'fr_FR').format(day)),
                        style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
                      ),
                      Text(
                        DateFormat('d MMMM yyyy', 'fr_FR').format(day),
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.primaryDark),
                      ),
                    ],
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _openForm(defaultDate: day);
                    },
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Ajouter'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Liste
            events.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Column(
                      children: [
                        Icon(Icons.event_available_outlined, size: 48, color: AppTheme.borderLight),
                        SizedBox(height: 12),
                        Text('Aucun événement ce jour', style: TextStyle(color: AppTheme.textSecondary)),
                      ],
                    ),
                  )
                : Flexible(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      shrinkWrap: true,
                      itemCount: events.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _sheetEventTile(events[i], ctx),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  Widget _sheetEventTile(CalendarEvent ev, BuildContext sheetCtx) {
    final isMarche = ev.type == 'marche';
    final typeColor = isMarche ? AppTheme.primary : const Color(0xFF2980B9);
    final typeLight = isMarche ? AppTheme.primaryFaded : const Color(0x142980B9);
    final typeIcon = isMarche ? Icons.store_mall_directory_outlined : Icons.event_note_outlined;

    final start = DateTime.tryParse(ev.date);
    final end = ev.endDate.isNotEmpty && ev.endDate != ev.date ? DateTime.tryParse(ev.endDate) : null;
    String dateLabel;
    if (start != null && end != null) {
      final days = end.difference(start).inDays + 1;
      dateLabel = '${DateFormat('d MMM', 'fr_FR').format(start)} → ${DateFormat('d MMM', 'fr_FR').format(end)}  ·  $days j';
    } else if (start != null) {
      dateLabel = DateFormat('EEEE d MMMM', 'fr_FR').format(start);
    } else {
      dateLabel = ev.date;
    }

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderLight),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: typeColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(color: typeLight, borderRadius: BorderRadius.circular(6)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(typeIcon, size: 11, color: typeColor),
                                const SizedBox(width: 4),
                                Text(
                                  isMarche ? 'Marché' : 'RDV',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: typeColor),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          SizedBox(
                            height: 28,
                            width: 28,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              icon: const Icon(Icons.edit_outlined, size: 16, color: AppTheme.primary),
                              onPressed: () {
                                Navigator.pop(sheetCtx);
                                _openForm(editing: ev);
                              },
                            ),
                          ),
                          SizedBox(
                            height: 28,
                            width: 28,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              icon: const Icon(Icons.delete_outline, size: 16, color: AppTheme.danger),
                              onPressed: () async {
                                Navigator.pop(sheetCtx);
                                await _delete(ev);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        ev.name,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppTheme.primaryDark),
                      ),
                      const SizedBox(height: 4),
                      Row(children: [
                        const Icon(Icons.schedule_outlined, size: 12, color: AppTheme.textLight),
                        const SizedBox(width: 4),
                        Expanded(child: Text(dateLabel, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary))),
                      ]),
                      if (ev.location.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Row(children: [
                          const Icon(Icons.location_on_outlined, size: 12, color: AppTheme.textLight),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(ev.location,
                                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                                overflow: TextOverflow.ellipsis),
                          ),
                        ]),
                      ],
                      if (ev.notes.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: AppTheme.background, borderRadius: BorderRadius.circular(8)),
                          child: Text(
                            ev.notes,
                            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary, fontStyle: FontStyle.italic),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : SafeArea(
              child: TableCalendar<CalendarEvent>(
                firstDay: DateTime.utc(2020),
                lastDay: DateTime.utc(2030),
                focusedDay: _focusedDay,
                selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                eventLoader: _eventsForDay,
                startingDayOfWeek: StartingDayOfWeek.monday,
                rowHeight: 76,
                calendarFormat: CalendarFormat.month,
                availableCalendarFormats: const {CalendarFormat.month: 'Mois'},
                calendarStyle: const CalendarStyle(
                  todayDecoration: BoxDecoration(color: AppTheme.accentLight, shape: BoxShape.circle),
                  todayTextStyle: TextStyle(color: AppTheme.primaryDark, fontWeight: FontWeight.w700),
                  selectedDecoration: BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle),
                  selectedTextStyle: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  outsideDaysVisible: false,
                  weekendTextStyle: TextStyle(color: AppTheme.accent),
                  defaultTextStyle: TextStyle(color: AppTheme.textColor),
                ),
                calendarBuilders: CalendarBuilders(
                  markerBuilder: (context, day, events) {
                    if (events.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ...events.take(2).map((ev) {
                            final color = ev.type == 'marche' ? AppTheme.primary : const Color(0xFF2980B9);
                            return Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 1),
                              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
                              child: Text(
                                ev.name,
                                style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            );
                          }),
                          if (events.length > 2)
                            Text(
                              '+${events.length - 2}',
                              style: const TextStyle(color: AppTheme.textLight, fontSize: 8, fontWeight: FontWeight.w600),
                            ),
                        ],
                      ),
                    );
                  },
                ),
                headerStyle: HeaderStyle(
                  titleCentered: true,
                  formatButtonVisible: false,
                  titleTextStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppTheme.primaryDark),
                  headerPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                  leftChevronIcon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: AppTheme.primaryFaded, borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.chevron_left, color: AppTheme.primary, size: 18),
                  ),
                  rightChevronIcon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: AppTheme.primaryFaded, borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.chevron_right, color: AppTheme.primary, size: 18),
                  ),
                ),
                daysOfWeekStyle: const DaysOfWeekStyle(
                  weekdayStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textLight),
                  weekendStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.accent),
                ),
                onDaySelected: (selected, focused) {
                  setState(() {
                    _selectedDay = selected;
                    _focusedDay = focused;
                  });
                  _showDaySheet(selected);
                },
                onPageChanged: (focused) => _focusedDay = focused,
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(defaultDate: _selectedDay),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Événement'),
      ),
    );
  }
}

// ─── Form ───

class _EventForm extends StatefulWidget {
  final CalendarEvent? editing;
  final DateTime? defaultDate;
  final void Function(CalendarEvent) onSave;

  const _EventForm({this.editing, this.defaultDate, required this.onSave});

  @override
  State<_EventForm> createState() => _EventFormState();
}

class _EventFormState extends State<_EventForm> {
  final _formKey = GlobalKey<FormState>();
  late String _name, _type, _date, _endDate, _location, _notes;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    _name = e?.name ?? '';
    _type = e?.type ?? 'marche';
    _date = e?.date ?? (widget.defaultDate != null ? DateFormat('yyyy-MM-dd').format(widget.defaultDate!) : DateFormat('yyyy-MM-dd').format(DateTime.now()));
    _endDate = e?.endDate ?? '';
    _location = e?.location ?? '';
    _notes = e?.notes ?? '';
  }

  Future<void> _pickDate(bool isEnd) async {
    final initial = DateTime.tryParse(isEnd && _endDate.isNotEmpty ? _endDate : _date) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      locale: const Locale('fr', 'FR'),
    );
    if (picked != null) {
      setState(() {
        if (isEnd) {
          _endDate = DateFormat('yyyy-MM-dd').format(picked);
        } else {
          _date = DateFormat('yyyy-MM-dd').format(picked);
        }
      });
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    final now = DateTime.now();
    widget.onSave(CalendarEvent(
      id: widget.editing?.id ?? const Uuid().v4(),
      name: _name.trim(),
      type: _type,
      date: _date,
      endDate: _endDate,
      location: _location.trim(),
      notes: _notes.trim(),
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
                widget.editing != null ? 'Modifier l\'événement' : 'Nouvel événement',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.primaryDark),
              ),
              const SizedBox(height: 16),
              // Type toggle
              Row(
                children: [
                  _typeBtn('Marché', 'marche'),
                  const SizedBox(width: 10),
                  _typeBtn('RDV', 'rdv'),
                ],
              ),
              const SizedBox(height: 14),
              TextFormField(
                initialValue: _name,
                decoration: const InputDecoration(labelText: 'Nom *'),
                validator: (v) => v == null || v.trim().isEmpty ? 'Requis' : null,
                onSaved: (v) => _name = v ?? '',
              ),
              const SizedBox(height: 12),
              // Date
              GestureDetector(
                onTap: () => _pickDate(false),
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Date *', suffixIcon: Icon(Icons.calendar_today, size: 18)),
                  child: Text(_date.isNotEmpty ? _date : 'Choisir une date'),
                ),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => _pickDate(true),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Date de fin (optionnel)',
                    suffixIcon: _endDate.isNotEmpty
                        ? GestureDetector(
                            onTap: () => setState(() => _endDate = ''),
                            child: const Icon(Icons.clear, size: 18))
                        : const Icon(Icons.calendar_today, size: 18),
                  ),
                  child: Text(_endDate.isNotEmpty ? _endDate : 'Optionnel'),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: _location,
                decoration: const InputDecoration(labelText: 'Lieu', prefixText: '📍 '),
                onSaved: (v) => _location = v ?? '',
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

  Widget _typeBtn(String label, String value) {
    final active = _type == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _type = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? AppTheme.primary : AppTheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: active ? AppTheme.primary : AppTheme.borderLight),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w700, color: active ? Colors.white : AppTheme.textSecondary),
          ),
        ),
      ),
    );
  }
}
