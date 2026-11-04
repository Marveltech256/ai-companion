import 'package:flutter/material.dart';

/// Inline fields in the existing memory editor; unset values stay unknown.
class MemoryDetails extends StatefulWidget {
  const MemoryDetails({
    super.key,
    required this.category,
    required this.attributes,
  });
  final String category;
  final Map<String, dynamic> attributes;
  @override
  State<MemoryDetails> createState() => _MemoryDetailsState();
}

class _MemoryDetailsState extends State<MemoryDetails> {
  Map<String, dynamic> get a => widget.attributes;
  Future<void> time(String key) async {
    final old = a[key] as int?;
    final result = await showTimePicker(
      context: context,
      initialTime: old == null
          ? TimeOfDay.now()
          : TimeOfDay(hour: old ~/ 60, minute: old % 60),
    );
    if (result != null && mounted) {
      setState(() => a[key] = result.hour * 60 + result.minute);
    }
  }

  String label(String key, String title) {
    final m = a[key] as int?;
    return m == null
        ? '$title (not set)'
        : '$title: ${TimeOfDay(hour: m ~/ 60, minute: m % 60).format(context)}';
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (widget.category == 'identity') ...[
        DropdownButtonFormField<String>(
          initialValue: a['field'] as String?,
          decoration: const InputDecoration(
            labelText: 'Personal detail (optional)',
          ),
          items: [
            for (final f in [
              'preferred_name',
              'full_name',
              'location',
              'timezone',
              'language',
            ])
              DropdownMenuItem(value: f, child: Text(f.replaceAll('_', ' '))),
          ],
          onChanged: (v) => setState(() => a['field'] = v),
        ),
        TextFormField(
          initialValue: a['value'] as String?,
          maxLength: 160,
          decoration: const InputDecoration(labelText: 'Value (optional)'),
          onChanged: (v) {
            if (v.trim().isEmpty) {
              a.remove('value');
            } else {
              a['value'] = v.trim();
            }
          },
        ),
      ],
      if (widget.category == 'routines') ...[
        DropdownButtonFormField<String>(
          initialValue: a['routine_kind'] as String?,
          decoration: const InputDecoration(labelText: 'Activity (optional)'),
          items: [
            for (final f in [
              'wake',
              'sleep',
              'work',
              'study',
              'exercise',
              'activity',
              'other',
            ])
              DropdownMenuItem(value: f, child: Text(f)),
          ],
          onChanged: (v) => setState(() => a['routine_kind'] = v),
        ),
        Wrap(
          spacing: 4,
          children: [
            for (var i = 0; i < 7; i++)
              FilterChip(
                label: Text(
                  const ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][i],
                ),
                selected: (a['weekdays'] as List? ?? []).contains(i),
                onSelected: (v) => setState(() {
                  final days = List<int>.from(a['weekdays'] as List? ?? []);
                  if (v) {
                    days.add(i);
                  } else {
                    days.remove(i);
                  }
                  a['weekdays'] = days;
                }),
              ),
          ],
        ),
        Wrap(
          children: [
            TextButton(
              onPressed: () => time('start_minute'),
              child: Text(label('start_minute', 'Starts')),
            ),
            TextButton(
              onPressed: () => time('end_minute'),
              child: Text(label('end_minute', 'Ends')),
            ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Avoid interruptions during this activity'),
          value:
              a['block_notifications'] as bool? ??
              {'work', 'sleep'}.contains(a['routine_kind']),
          onChanged: (v) => setState(() => a['block_notifications'] = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Skip this activity on the exception date'),
          value: a['skip'] == true,
          onChanged: (v) => setState(() => a['skip'] = v),
        ),
      ],
      if (widget.category == 'events') ...[
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Repeats every year'),
          subtitle: const Text(
            'For a birthday or anniversary you want to keep.',
          ),
          value: a['annual'] == true,
          onChanged: (v) => setState(() => a['annual'] = v),
        ),
        if (a['annual'] == true)
          Row(
            children: [
              for (final field in ['month', 'day'])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: TextFormField(
                      initialValue: a[field]?.toString(),
                      decoration: InputDecoration(
                        labelText: field == 'month' ? 'Month (1–12)' : 'Day',
                      ),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        final m = field == 'month' ? n : a['month'] as int?;
                        final d = field == 'day' ? n : a['day'] as int?;
                        if (n == null ||
                            m == null ||
                            d == null ||
                            m < 1 ||
                            m > 12 ||
                            d < 1 ||
                            d > 31) {
                          return 'Use a valid date.';
                        }
                        final date = DateTime(2000, m, d);
                        return date.month == m && date.day == d
                            ? null
                            : 'Use a valid date.';
                      },
                      onChanged: (v) {
                        final n = int.tryParse(v);
                        if (n == null) {
                          a.remove(field);
                        } else {
                          a[field] = n;
                        }
                      },
                    ),
                  ),
                ),
            ],
          ),
      ],
      if ((widget.category == 'events' && a['annual'] != true) ||
          widget.category == 'routines') ...[
        TextFormField(
          initialValue: a['on_date'] as String?,
          decoration: InputDecoration(
            labelText: widget.category == 'routines'
                ? 'Exception date, YYYY-MM-DD (optional)'
                : 'Event date, YYYY-MM-DD (optional)',
          ),
          validator: (v) {
            if (v == null || v.trim().isEmpty) {
              return widget.category == 'routines' && a['skip'] == true
                  ? 'Choose an exception date.'
                  : null;
            }
            final d = DateTime.tryParse(v.trim());
            return d != null && d.toIso8601String().substring(0, 10) == v.trim()
                ? null
                : 'Use a valid YYYY-MM-DD date.';
          },
          onChanged: (v) {
            a.remove('relative_days');
            a.remove('observed_at');
            if (v.trim().isEmpty) {
              a.remove('on_date');
            } else {
              a['on_date'] = v.trim();
            }
          },
        ),
      ],
      if (widget.category == 'events')
        DropdownButtonFormField<String>(
          initialValue: a['event_status'] as String?,
          decoration: const InputDecoration(
            labelText: 'Event status (optional)',
          ),
          items: [
            for (final f in ['planned', 'completed', 'cancelled', 'uncertain'])
              DropdownMenuItem(value: f, child: Text(f)),
          ],
          onChanged: (v) => setState(() => a['event_status'] = v),
        ),
    ],
  );
}
