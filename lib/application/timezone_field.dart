import 'package:flutter/material.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

/// Uses the OS/browser IANA zone. No IP/location lookup is necessary.
class TimezoneField extends StatefulWidget {
  const TimezoneField({
    super.key,
    required this.controller,
    this.automatic,
    this.onAutomaticChanged,
    this.requiredValue = true,
  });
  final TextEditingController controller;
  final bool? automatic;
  final ValueChanged<bool>? onAutomaticChanged;
  final bool requiredValue;
  @override
  State<TimezoneField> createState() => _TimezoneFieldState();
}

class _TimezoneFieldState extends State<TimezoneField> {
  final _focus = FocusNode();
  List<String> _zones = [
    'Africa/Kampala',
    'Africa/Nairobi',
    'UTC',
    'Europe/London',
    'America/New_York',
    'Asia/Dubai',
    'Asia/Kolkata',
    'Asia/Tokyo',
    'Australia/Sydney',
  ];
  String? _detected;
  bool _edited = false;
  late bool _automatic;
  @override
  void initState() {
    super.initState();
    _automatic = widget.automatic ?? widget.controller.text.isEmpty;
    _load();
  }

  Future<void> _load() async {
    String? local;
    List<String>? zones;
    try {
      local = (await FlutterTimezone.getLocalTimezone()).identifier;
    } catch (_) {}
    try {
      zones =
          (await FlutterTimezone.getAvailableTimezones())
              .map((z) => z.identifier)
              .toSet()
              .toList()
            ..sort();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _detected = local;
      if (zones != null && zones.isNotEmpty) _zones = zones;
      if (local != null && !_zones.contains(local)) _zones.add(local);
      if (widget.controller.text.isNotEmpty &&
          !_zones.contains(widget.controller.text)) {
        _zones.add(widget.controller.text);
      }
      if (local != null && _automatic && !_edited) {
        widget.controller.text = local;
        widget.onAutomaticChanged?.call(true);
      }
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      RawAutocomplete<String>(
        textEditingController: widget.controller,
        focusNode: _focus,
        optionsBuilder: (value) {
          final q = value.text.toLowerCase().replaceAll(' ', '_');
          return _zones.where((z) => z.toLowerCase().contains(q)).take(40);
        },
        onSelected: (value) {
          widget.controller.text = value;
          _edited = true;
          _automatic = false;
          widget.onAutomaticChanged?.call(false);
          setState(() {});
        },
        fieldViewBuilder: (context, controller, focus, submit) => TextFormField(
          controller: controller,
          focusNode: focus,
          decoration: InputDecoration(
            labelText: 'Time zone',
            hintText: 'Search your city',
            suffixIcon: IconButton(
              tooltip: 'Choose a time zone',
              icon: const Icon(Icons.arrow_drop_down),
              onPressed: () {
                focus.requestFocus();
                controller.selection = TextSelection(
                  baseOffset: 0,
                  extentOffset: controller.text.length,
                );
              },
            ),
          ),
          onChanged: (_) {
            _edited = true;
            _automatic = false;
            widget.onAutomaticChanged?.call(false);
          },
          validator: (value) =>
              widget.requiredValue && (value ?? '').trim().isEmpty
              ? 'Choose your time zone.'
              : null,
          onFieldSubmitted: (_) => submit(),
        ),
        optionsViewBuilder: (context, select, options) => Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 5,
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 310,
              height: 220,
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (final zone in options)
                    ListTile(
                      dense: true,
                      title: Text(zone.replaceAll('_', ' ')),
                      onTap: () => select(zone),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      TextButton.icon(
        onPressed: _detected == null
            ? null
            : () {
                setState(() {
                  _automatic = true;
                  _edited = false;
                  widget.controller.text = _detected!;
                });
                widget.onAutomaticChanged?.call(true);
              },
        icon: const Icon(Icons.my_location, size: 16),
        label: Text(
          _automatic && _detected != null
              ? 'Using device time zone'
              : 'Use device time zone',
        ),
      ),
    ],
  );
}
