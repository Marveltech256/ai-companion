import 'package:flutter/material.dart';

const ink = Color(0xFF302638);
const plum = Color(0xFF61476D);
const mutedInk = Color(0xFF7B737F);
const paper = Color(0xFFF9F7F2);
const lilac = Color(0xFFEEE8F3);
const line = Color(0xFFE7E1E7);
const interests = [
  'Art & making',
  'Music',
  'Little adventures',
  'Books',
  'Cooking',
];
const styles = ['Gentle & warm', 'Playful', 'Reflective'];
const memoryCategories = [
  'identity',
  'routines',
  'preferences',
  'relationships',
  'events',
  'conversation_history',
  'personal_development',
];
String canonicalMemoryCategory(String category) => switch (category) {
  'personal_information' => 'identity',
  'people' => 'relationships',
  'important_dates' => 'events',
  'goals' => 'personal_development',
  'experiences' || 'discussions' => 'conversation_history',
  'communication_preferences' => 'preferences',
  _ => category,
};

ThemeData morrowTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: plum, surface: paper);
  return ThemeData(
    useMaterial3: true,
    splashFactory: InkRipple.splashFactory,
    colorScheme: scheme,
    scaffoldBackgroundColor: paper,
    fontFamily: 'Inter',
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontFamily: 'Lora',
        fontSize: 32,
        color: ink,
        height: 1.25,
      ),
      headlineMedium: TextStyle(
        fontFamily: 'Lora',
        fontSize: 26,
        color: ink,
        height: 1.3,
      ),
      titleLarge: TextStyle(
        fontFamily: 'Lora',
        fontSize: 21,
        color: ink,
        height: 1.35,
      ),
      bodyLarge: TextStyle(fontSize: 15, color: ink, height: 1.65),
      bodyMedium: TextStyle(fontSize: 13, color: ink, height: 1.55),
      bodySmall: TextStyle(fontSize: 11, color: mutedInk, height: 1.5),
    ),
    dividerTheme: const DividerThemeData(color: line, thickness: 1),
    appBarTheme: const AppBarTheme(
      backgroundColor: paper,
      foregroundColor: ink,
      surfaceTintColor: Colors.transparent,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: plum,
        foregroundColor: Colors.white,
        minimumSize: const Size(48, 50),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: const TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(44, 46),
        foregroundColor: plum,
        side: const BorderSide(color: line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 17, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: plum, width: 1.5),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white,
      selectedColor: lilac,
      side: const BorderSide(color: line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      labelStyle: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 12,
        color: plum,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: paper,
      indicatorColor: lilac,
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 11, fontFamily: 'Inter', color: plum),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: plum,
    ),
  );
}

class Brand extends StatelessWidget {
  const Brand({super.key});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.asset(
          'assets/branding/logo-mark.png',
          width: 36,
          height: 36,
          excludeFromSemantics: true,
        ),
      ),
      const SizedBox(width: 9),
      const Flexible(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            'Ai Companion',
            style: TextStyle(
              fontFamily: 'Lora',
              color: Color(0xFF4B087D),
              fontSize: 29,
            ),
          ),
        ),
      ),
    ],
  );
}

/// Decorative artwork only. The application around it is normal Flutter layout.
class LumiOrb extends StatelessWidget {
  const LumiOrb({super.key, this.size = 120, this.active = false});
  final double size;
  final bool active;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Your companion',
    image: true,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment(-.45, -.6),
          radius: 1,
          colors: [
            Color(0xFFFFF9E9),
            Color(0xFFD8C6E4),
            Color(0xFFA88CC0),
            Color(0xFF795A92),
          ],
          stops: [0, .3, .65, 1],
        ),
        boxShadow: [
          BoxShadow(
            color: plum.withValues(alpha: active ? .24 : .12),
            blurRadius: active ? 36 : 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          size * .22,
          size * .02,
          size * .05,
          size * .3,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: .45),
              width: 1.5,
            ),
          ),
        ),
      ),
    ),
  );
}

class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.color = Colors.white,
    this.padding = const EdgeInsets.all(22),
  });
  final Widget child;
  final Color color;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Material(
    color: color,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
      side: const BorderSide(color: line),
    ),
    child: Padding(padding: padding, child: child),
  );
}

class PageHeading extends StatelessWidget {
  const PageHeading(this.title, this.subtitle, {super.key, this.action});
  final String title, subtitle;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 12,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 6),
            Text(subtitle, style: const TextStyle(color: mutedInk)),
          ],
        ),
        ?action,
      ],
    ),
  );
}

class ActionButton extends StatefulWidget {
  const ActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.secondary = false,
  });
  final String label;
  final Future<void> Function()? onPressed;
  final IconData? icon;
  final bool secondary;
  @override
  State<ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<ActionButton> {
  bool busy = false;
  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy)
          const SizedBox(
            width: 17,
            height: 17,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else if (widget.icon != null)
          Icon(widget.icon, size: 19),
        if (busy || widget.icon != null) const SizedBox(width: 10),
        Flexible(child: Text(widget.label)),
      ],
    );
    final callback = busy || widget.onPressed == null
        ? null
        : () async {
            setState(() => busy = true);
            try {
              await widget.onPressed!();
            } finally {
              if (mounted) setState(() => busy = false);
            }
          };
    return widget.secondary
        ? OutlinedButton(onPressed: callback, child: child)
        : FilledButton(onPressed: callback, child: child);
  }
}
