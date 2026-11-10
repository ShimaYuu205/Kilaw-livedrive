import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/util.dart';

class Pal {
  final Color bg, surface, surface2, border, text, dim, faint, accent, accentInk, accentDim, male, maleBg, female, femaleBg, warn, danger, good;
  const Pal(this.bg, this.surface, this.surface2, this.border, this.text, this.dim, this.faint, this.accent, this.accentInk,
      this.accentDim, this.male, this.maleBg, this.female, this.femaleBg, this.warn, this.danger, this.good);

  static const dark = Pal(Color(0xFF10161A), Color(0xFF182025), Color(0xFF1F2A30), Color(0xFF2B383F), Color(0xFFEAF1F3),
      Color(0xFF8FA3AB), Color(0xFF5E7079), Color(0xFF2FBBA6), Color(0xFF04231D), Color(0xFF1D5A50), Color(0xFF5BA6E6),
      Color(0xFF182734), Color(0xFFE58AB0), Color(0xFF2C1D26), Color(0xFFE3AE4E), Color(0xFFE2727B), Color(0xFF57C08B));
  static const light = Pal(Color(0xFFF1F5F4), Color(0xFFFFFFFF), Color(0xFFEAF0EE), Color(0xFFD8E2DF), Color(0xFF16232A),
      Color(0xFF5C7078), Color(0xFF90A0A5), Color(0xFF0E8074), Color(0xFFFFFFFF), Color(0xFFCFEAE6), Color(0xFF1E6FB8),
      Color(0xFFE4F0FA), Color(0xFFC23F73), Color(0xFFFBE7EF), Color(0xFF93630F), Color(0xFFB4333D), Color(0xFF1F7A4C));
}

Pal pal = Pal.dark;

ThemeData buildTheme(bool light) {
  pal = light ? Pal.light : Pal.dark;
  final base = light ? ThemeData.light(useMaterial3: true) : ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: pal.bg,
    colorScheme: base.colorScheme.copyWith(
      primary: pal.accent, onPrimary: pal.accentInk, surface: pal.surface, onSurface: pal.text, error: pal.danger,
      secondary: pal.accent, outline: pal.border, surfaceContainerHighest: pal.surface2,
    ),
    appBarTheme: AppBarTheme(backgroundColor: pal.surface, foregroundColor: pal.text, elevation: 0, scrolledUnderElevation: 0),
    cardTheme: CardThemeData(color: pal.surface, elevation: 0, margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: pal.border))),
    dialogTheme: DialogThemeData(backgroundColor: pal.surface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    dividerTheme: DividerThemeData(color: pal.border, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: pal.surface2, isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: pal.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: pal.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: pal.accent, width: 1.4)),
      hintStyle: TextStyle(color: pal.faint, fontSize: 13),
      labelStyle: TextStyle(color: pal.dim, fontSize: 13),
    ),
    textTheme: base.textTheme.apply(bodyColor: pal.text, displayColor: pal.text),
  );
}

// ---------------- toast ----------------
final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey<ScaffoldMessengerState>();

void toast(String msg, [String kind = 'ok']) {
  final c = kind == 'warn' ? pal.warn : kind == 'err' ? pal.danger : pal.accent;
  final m = messengerKey.currentState;
  if (m == null) return;
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Text(msg, style: TextStyle(color: kind == 'ok' ? pal.accentInk : Colors.black, fontWeight: FontWeight.w600)),
    backgroundColor: c,
    behavior: SnackBarBehavior.floating,
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    duration: const Duration(milliseconds: 3200),
  ));
}

Future<bool> confirmDialog(BuildContext c, String msg, {String ok = 'Ya'}) async {
  final r = await showDialog<bool>(
    context: c,
    builder: (ctx) => AlertDialog(
      content: Text(msg),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ok)),
      ],
    ),
  );
  return r == true;
}

/// Dialog formulir responsif: lebar maksimum nyaman di tablet/desktop, layar penuh di HP.
Future<T?> showSheet<T>(BuildContext c, {required String title, required Widget Function(BuildContext) body, List<Widget>? actions, double maxWidth = 560}) {
  return showDialog<T>(
    context: c,
    barrierDismissible: false,
    builder: (ctx) {
      final narrow = MediaQuery.of(ctx).size.width < 600;
      return Dialog(
        insetPadding: narrow ? const EdgeInsets.all(8) : const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: MediaQuery.of(ctx).size.height * 0.92),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 6, 0),
              child: Row(children: [
                Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
              ]),
            ),
            Flexible(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(18, 4, 18, 14), child: body(ctx))),
            if (actions != null) Padding(padding: const EdgeInsets.fromLTRB(18, 0, 18, 14), child: Row(children: actions)),
          ]),
        ),
      );
    },
  );
}

// ---------------- widget kecil ----------------
class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsets? margin;
  const Panel({super.key, required this.child, this.margin});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: margin ?? const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: pal.border)),
        child: child,
      );
}

class Hint extends StatelessWidget {
  final String text;
  final Color? color;
  const Hint(this.text, {super.key, this.color});
  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(text, style: TextStyle(color: color ?? pal.dim, fontSize: 12.5, height: 1.4)));
}

class CountPill extends StatelessWidget {
  final int n;
  const CountPill(this.n, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: pal.accentDim, borderRadius: BorderRadius.circular(20)),
        child: Text('$n', style: TextStyle(color: pal.accent, fontSize: 12, fontWeight: FontWeight.w700)),
      );
}

class H3 extends StatelessWidget {
  final String text;
  final int? count;
  const H3(this.text, {super.key, this.count});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
        if (count != null) CountPill(count!),
      ]);
}

class StatCard extends StatelessWidget {
  final String label, value;
  final Color? color;
  const StatCard(this.label, this.value, {super.key, this.color});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: pal.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: pal.dim, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color ?? pal.text)),
        ]),
      );
}

/// Grid statistik: 3 kolom di layar lebar, 2 di sempit.
class StatGrid extends StatelessWidget {
  final List<Widget> children;
  const StatGrid(this.children, {super.key});
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (c, cs) {
        final cols = cs.maxWidth >= 520 ? 3 : 2;
        final w = (cs.maxWidth - (cols - 1) * 10) / cols;
        return Wrap(spacing: 10, runSpacing: 10, children: [for (final ch in children) SizedBox(width: w, child: ch)]);
      });
}

class Btn extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  final bool accent, small;
  final Color? color;
  const Btn(this.text, this.onTap, {super.key, this.accent = false, this.small = false, this.color});
  @override
  Widget build(BuildContext context) {
    final pad = EdgeInsets.symmetric(horizontal: small ? 10 : 16, vertical: small ? 6 : 11);
    final st = TextStyle(fontSize: small ? 12 : 13.5, fontWeight: FontWeight.w700);
    if (accent) {
      return FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(backgroundColor: color ?? pal.accent, foregroundColor: pal.accentInk, padding: pad, textStyle: st,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
        child: Text(text),
      );
    }
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(foregroundColor: color ?? pal.text, side: BorderSide(color: pal.border), padding: pad, textStyle: st,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
      child: Text(text),
    );
  }
}

class Field extends StatelessWidget {
  final String label;
  final TextEditingController c;
  final String? hint;
  final TextInputType? type;
  final int lines;
  final bool readOnly;
  final ValueChanged<String>? onChanged;
  final FocusNode? focus;
  final List<TextInputFormatter>? formatters;
  const Field(this.label, this.c, {super.key, this.hint, this.type, this.lines = 1, this.readOnly = false, this.onChanged, this.focus, this.formatters});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (label.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(label, style: TextStyle(color: pal.dim, fontSize: 12, fontWeight: FontWeight.w700))),
          TextField(controller: c, focusNode: focus, keyboardType: type, maxLines: lines, minLines: lines, readOnly: readOnly, onChanged: onChanged,
              inputFormatters: formatters, decoration: InputDecoration(hintText: hint)),
        ]),
      );
}

/// Kolom tanggal (nilai ISO yyyy-MM-dd) dengan pemilih tanggal.
class DateField extends StatelessWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final bool allowClear;
  const DateField(this.label, this.value, this.onChanged, {super.key, this.allowClear = true});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (label.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(label, style: TextStyle(color: pal.dim, fontSize: 12, fontWeight: FontWeight.w700))),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () async {
              final init = parseIso(value) ?? DateTime.now();
              final d = await showDatePicker(context: context, initialDate: init, firstDate: DateTime(1900), lastDate: DateTime(2100));
              if (d != null) onChanged(isoOf(d));
            },
            child: InputDecorator(
              decoration: InputDecoration(suffixIcon: allowClear && value.isNotEmpty
                  ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => onChanged(''))
                  : const Icon(Icons.calendar_today, size: 18)),
              child: Text(value.isEmpty ? '—' : '${fmtIsoShort(value)} (${hariFromIso(value)})', style: TextStyle(color: value.isEmpty ? pal.faint : pal.text)),
            ),
          ),
        ]),
      );
}

/// Tombol pilihan bergantian (segmented).
class Pills extends StatelessWidget {
  final List<(String, String)> options; // (nilai, label)
  final String value;
  final ValueChanged<String> onChanged;
  final Color? onColor;
  const Pills(this.options, this.value, this.onChanged, {super.key, this.onColor});
  @override
  Widget build(BuildContext context) => Wrap(spacing: 6, runSpacing: 6, children: [
        for (final o in options)
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => onChanged(o.$1),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: value == o.$1 ? (onColor ?? pal.accent) : pal.surface2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: value == o.$1 ? (onColor ?? pal.accent) : pal.border),
              ),
              child: Text(o.$2, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: value == o.$1 ? pal.accentInk : pal.text)),
            ),
          ),
      ]);
}

class Empty extends StatelessWidget {
  final String text;
  const Empty(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.all(22), child: Center(child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: pal.faint))));
}

class GenderDot extends StatelessWidget {
  final String g;
  const GenderDot(this.g, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        width: 9, height: 9, margin: const EdgeInsets.only(right: 6),
        decoration: BoxDecoration(shape: BoxShape.circle, color: g == 'p' ? pal.female : g == 'l' ? pal.male : pal.faint),
      );
}

/// Saran (autocomplete) sederhana di bawah kolom: daftar item yang bisa diketuk.
class SuggestList extends StatelessWidget {
  final List<(String, String)> items; // (judul, sub)
  final ValueChanged<int> onPick;
  const SuggestList(this.items, this.onPick, {super.key});
  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: pal.surface2, border: Border.all(color: pal.border), borderRadius: BorderRadius.circular(8)),
      child: Column(children: [
        for (var i = 0; i < items.length; i++)
          InkWell(
            onTap: () => onPick(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(children: [
                Expanded(child: Text(items[i].$1, style: const TextStyle(fontWeight: FontWeight.w700))),
                if (items[i].$2.isNotEmpty) Flexible(child: Text(items[i].$2, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.dim, fontSize: 12))),
              ]),
            ),
          ),
      ]),
    );
  }
}

Widget gap([double h = 10]) => SizedBox(height: h);
