import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';

import 'theme.dart';

/// Card surface: radius 16, 1 px border, very light shadow.
class LekkaCard extends StatelessWidget {
  const LekkaCard({super.key, required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final p = LekkaPalette.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.line),
        boxShadow: const [
          BoxShadow(color: Color(0x0A0F172A), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: child,
    );
  }
}

/// Logo tile: rounded square in primary green with the white Telugu letter ల.
class LogoTile extends StatelessWidget {
  const LogoTile({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: LekkaColors.primary,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      // The letter is the logo, not translatable text.
      child: Text(
        'ల',
        textScaler: TextScaler.noScaling,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontSize: size * 0.5,
              height: 1.1,
            ),
      ),
    );
  }
}

/// Two-option switch on a chip-coloured track. The active option is green
/// with white text. Each option is at least 44 px tall, and labels wrap
/// rather than clip when Telugu or Hindi text is long.
class SegmentedSwitch<T> extends StatelessWidget {
  const SegmentedSwitch({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.compact = false,
  });

  final List<(T, String)> options;
  final T selected;
  final ValueChanged<T> onChanged;

  /// Compact: shrink-wraps its labels (used for the small Loans/Chits pill).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = LekkaPalette.of(context);
    final textStyle = Theme.of(context).textTheme.labelLarge;

    Widget segment((T, String) option) {
      final active = option.$1 == selected;
      final child = Semantics(
        button: true,
        selected: active,
        child: Material(
          color: active ? LekkaColors.primary : Colors.transparent,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: active ? null : () => onChanged(option.$1),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 38),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 10, vertical: 8),
                child: Center(
                  widthFactor: compact ? 1 : null,
                  child: Text(
                    option.$2,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: textStyle?.copyWith(color: active ? Colors.white : p.muted),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      return compact ? child : Expanded(child: child);
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(999)),
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: options.map(segment).toList(),
        ),
      ),
    );
  }
}

/// Friendly empty state: icon in a green tint circle, title and a short line.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.body});

  final IconData icon;
  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) {
    final p = LekkaPalette.of(context);
    final t = Theme.of(context).textTheme;
    return LekkaCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: p.tint,
              shape: BoxShape.circle,
              border: Border.all(color: p.tintBorder),
            ),
            child: Icon(icon, color: p.accent),
          ),
          const SizedBox(height: 12),
          Text(title, style: t.titleMedium, textAlign: TextAlign.center),
          if (body != null) ...[
            const SizedBox(height: 6),
            Text(body!, style: t.bodyMedium?.copyWith(color: p.muted), textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }
}

/// Section heading with an optional action on the right ("See all").
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
          if (action != null) action!,
        ],
      ),
    );
  }
}

/// Shows a spinner while loading, an error card with "Try again" on failure,
/// and [builder] once the data is here.
class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({super.key, required this.value, required this.builder, required this.onRetry});

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return value.when(
      data: builder,
      loading: () => const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => LekkaCard(
        child: Column(
          children: [
            Text(l.loadError, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            TextButton(onPressed: onRetry, child: Text(l.tryAgain)),
          ],
        ),
      ),
    );
  }
}

/// Up to two initials from a name: "Bala Krishna" → "BK". Works for any script.
String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
  if (parts.isEmpty) return '•';
  String first(String s) => String.fromCharCodes(s.runes.take(1));
  return parts.length == 1 ? first(parts[0]).toUpperCase() : (first(parts[0]) + first(parts[1])).toUpperCase();
}

/// A form field that opens a picker (sheet or date picker) when tapped.
/// Looks like the text fields, and shows its error underneath like they do.
class PickerField extends StatelessWidget {
  const PickerField({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    this.placeholder,
    this.errorText,
  });

  final String label;
  final String? value;
  final String? placeholder;
  final IconData icon;
  final String? errorText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = LekkaPalette.of(context);
    return Semantics(
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            errorText: errorText,
            prefixIcon: Icon(icon),
            suffixIcon: const Icon(Icons.expand_more),
          ),
          child: Text(
            value ?? placeholder ?? '',
            style: t.bodyLarge?.copyWith(color: value == null ? p.muted : null),
          ),
        ),
      ),
    );
  }
}

/// A tinted note with an icon, for short explanations.
class InfoBanner extends StatelessWidget {
  const InfoBanner({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = LekkaPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.tint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.tintBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: p.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: p.text)),
          ),
        ],
      ),
    );
  }
}
