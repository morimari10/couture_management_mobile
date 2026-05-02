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
      // Multi-day events
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

  List<CalendarEvent> get _upcoming {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _events.where((e) {
      final d = DateTime.tryParse(e.date);
      return d != null && !d.isBefore(today);
    }).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
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
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Supprimer', style: TextStyle(color: AppTheme.danger))),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _events.removeWhere((e) => e.id == ev.id));
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    final selectedEvents = _selectedDay != null ? _eventsForDay(_selectedDay!) : <CalendarEvent>[];
    final upcoming = _upcoming;

    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : Column(
              children: [
                // ── Calendar card ──
                Material(
                  color: AppTheme.surface,
                  elevation: 2,
                  shadowColor: const Color(0x1A713131),
                  child: TableCalendar<CalendarEvent>(
                    firstDay: DateTime.utc(2020),
                    lastDay: DateTime.utc(2030),
                    focusedDay: _focusedDay,
                    selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                    eventLoader: _eventsForDay,
                    startingDayOfWeek: StartingDayOfWeek.monday,
                    calendarStyle: const CalendarStyle(
                      todayDecoration: BoxDecoration(color: AppTheme.accentLight, shape: BoxShape.circle),
                      todayTextStyle: TextStyle(color: AppTheme.primaryDark, fontWeight: FontWeight.w700),
                      selectedDecoration: BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle),
                      selectedTextStyle: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                      markerDecoration: BoxDecoration(color: AppTheme.accent, shape: BoxShape.circle),
                      markerSize: 5,
                      markersMaxCount: 3,
                      outsideDaysVisible: false,
                      weekendTextStyle: TextStyle(color: AppTheme.accent),
                      defaultTextStyle: TextStyle(color: AppTheme.textColor),
                    ),
                    headerStyle: HeaderStyle(
                      titleCentered: true,
                      formatButtonVisible: false,
                      titleTextStyle: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: AppTheme.primaryDark,
                      ),
                      headerPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                      leftChevronIcon: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryFaded,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.chevron_left, color: AppTheme.primary, size: 18),
                      ),
                      rightChevronIcon: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryFaded,
                          borderRadius: BorderRadius.circular(8),
                        ),
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
                    },
                    onPageChanged: (focused) => _focusedDay = focused,
                  ),
                ),
                // ── Events section ──
                Expanded(
                  child: selectedEvents.isEmpty && upcoming.isEmpty
                      ? _emptyState()
                      : RefreshIndicator(
                          onRefresh: _load,
                          color: AppTheme.accent,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                            children: [
                              // Selected day
                              if (_selectedDay != null) ...[
                                _sectionHeader(
                                  DateFormat('EEEE d MMMM', 'fr_FR').format(_selectedDay!),
                                  count: selectedEvents.length,
                                  icon: Icons.today_outlined,
                                ),
                                if (selectedEvents.isEmpty)
                                  _noEventsForDay()
                                else
                                  ...selectedEvents.map((e) => _eventCard(e)),
                                const SizedBox(height: 20),
                              ],
                              // Upcoming
                              if (upcoming.isNotEmpty) ...[
                                _sectionHeader(
                                  'Prochains événements',
                                  count: upcoming.length,
                                  icon: Icons.schedule_outlined,
                                ),
                                ...upcoming.take(10).map((e) => _upcomingCard(e)),
                              ],
                            ],
                          ),
                        ),
                ),
              ],
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

  Widget _sectionHeader(String title, {required int count, required IconData icon}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppTheme.textLight),
          const SizedBox(width: 6),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.textSecondary,
              letterSpacing: 0.3,
            ),
          ),
          if (count > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.primaryFaded,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.primary),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _noEventsForDay() {
    return GestureDetector(
      onTap: () => _openForm(defaultDate: _selectedDay),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: AppTheme.primaryFaded,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.borderLight),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_circle_outline, size: 15, color: AppTheme.textLight),
            SizedBox(width: 8),
            Text(
              'Aucun événement · appuyer pour en créer un',
              style: TextStyle(fontSize: 12, color: AppTheme.textLight),
            ),
          ],
        ),
      ),
    );
  }

  Widget _eventCard(CalendarEvent ev) {
    final isMarche = ev.type == 'marche';
    final typeColor = isMarche ? AppTheme.primary : const Color(0xFF2980B9);
    final typeLight = isMarche ? AppTheme.primaryFaded : const Color(0x142980B9);
    final typeIcon = isMarche ? Icons.store_mall_directory_outlined : Icons.event_note_outlined;
    final typeLabel = isMarche ? 'Marché' : 'RDV';

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
      margin: const EdgeInsets.only(bottom: 10),
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
              // Left accent bar
              Container(width: 4, color: typeColor),
              // Content
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
                                Text(typeLabel, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: typeColor)),
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
                              onPressed: () => _openForm(editing: ev),
                            ),
                          ),
                          SizedBox(
                            height: 28,
                            width: 28,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              icon: const Icon(Icons.delete_outline, size: 16, color: AppTheme.danger),
                              onPressed: () => _delete(ev),
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
                        Expanded(
                          child: Text(dateLabel, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                        ),
                      ]),
                      if (ev.location.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Row(children: [
                          const Icon(Icons.location_on_outlined, size: 12, color: AppTheme.textLight),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              ev.location,
                              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ]),
                      ],
                      if (ev.notes.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.background,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            ev.notes,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary,
                              fontStyle: FontStyle.italic,
                            ),
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

  Widget _upcomingCard(CalendarEvent ev) {
    final evDate = DateTime.tryParse(ev.date) ?? DateTime.now();
    final today = DateTime.now();
    final diff = DateTime(evDate.year, evDate.month, evDate.day)
        .difference(DateTime(today.year, today.month, today.day))
        .inDays;
    final isToday = diff == 0;
    final isTomorrow = diff == 1;
    final isMarche = ev.type == 'marche';
    final typeColor = isMarche ? AppTheme.primary : const Color(0xFF2980B9);
    final countdown = isToday ? "Aujourd'hui" : (isTomorrow ? 'Demain' : 'J − $diff');

    return GestureDetector(
      onTap: () => setState(() {
        _selectedDay = evDate;
        _focusedDay = evDate;
      }),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isToday ? AppTheme.primary : AppTheme.borderLight),
          boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 4, offset: Offset(0, 2))],
        ),
        child: Row(
          children: [
            // Date block
            Container(
              width: 60,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: isToday ? AppTheme.primary : AppTheme.primaryFaded,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(11)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    DateFormat('d', 'fr_FR').format(evDate),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                      color: isToday ? Colors.white : AppTheme.primary,
                    ),
                  ),
                  Text(
                    DateFormat('MMM', 'fr_FR').format(evDate).toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: isToday ? Colors.white70 : AppTheme.textLight,
                    ),
                  ),
                ],
              ),
            ),
            // Name + location
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ev.name,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.primaryDark),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (ev.location.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(children: [
                        const Icon(Icons.location_on_outlined, size: 11, color: AppTheme.textLight),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            ev.location,
                            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ]),
                    ],
                  ],
                ),
              ),
            ),
            // Countdown + type icon
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isToday ? AppTheme.primary : AppTheme.primaryFaded,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      countdown,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: isToday ? Colors.white : AppTheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Icon(
                    isMarche ? Icons.store_mall_directory_outlined : Icons.event_note_outlined,
                    size: 14,
                    color: typeColor,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() => ListView(
        children: const [
          SizedBox(height: 60),
          Icon(Icons.event_available_outlined, size: 64, color: AppTheme.borderLight),
          SizedBox(height: 16),
          Text(
            'Aucun événement prévu',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
          ),
          SizedBox(height: 8),
          Text(
            'Sélectionnez un jour ou appuyez sur + pour créer un événement.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppTheme.textLight),
          ),
        ],
      );
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
