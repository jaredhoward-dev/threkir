import 'package:flutter/material.dart';

import '../theme/spacing.dart';
import 'edge_fade_scroll.dart';
import 'hub_tab_body.dart';
import 'sheet_scaffold.dart';

/// The one search field: a search glyph, the hint, and a clear button while
/// there is text. Every list's search is this widget, so clear is always
/// there and always in the same place (issue #1374: 11 of 20 hand-built
/// search fields had none).
///
/// Strings come from the caller because ui_kit has no catalogue.
class AppSearchField extends StatefulWidget {
  const AppSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.clearTooltip,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.autofocus = false,
    this.onClose,
  });

  final TextEditingController controller;
  final String hint;

  /// The clear button's tooltip and screen-reader label.
  final String clearTooltip;

  /// Also called with `''` when the clear button empties the field.
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final bool autofocus;

  /// When set, the clear button shows even with no text, and after clearing
  /// it calls this: a search opened from an icon closes back to it.
  final VoidCallback? onClose;

  /// This field with [onClose] set and [focusNode] given if it had none,
  /// for a host that opens it from an icon and focuses it itself.
  AppSearchField opened({
    required VoidCallback onClose,
    required FocusNode focusNode,
  }) =>
      AppSearchField(
        key: key,
        controller: controller,
        hint: hint,
        clearTooltip: clearTooltip,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        focusNode: this.focusNode ?? focusNode,
        autofocus: autofocus,
        onClose: onClose,
      );

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  /// Whether this field last asked its hub tab's control row to stay.
  bool _holding = false;

  /// The hub tab's control row this field sits in, if any.
  late final HubControlsHold? _row = HubTabBody.controlsOf(context);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onText);
    _syncHold();
  }

  @override
  void didUpdateWidget(AppSearchField old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onText);
      widget.controller.addListener(_onText);
      _syncHold();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    if (_holding) _row?.hold(this, false);
    super.dispose();
  }

  void _onText() {
    if (!mounted) return;
    setState(() {});
    _syncHold();
  }

  /// A live query is a filter that is on, so it keeps a hub tab's control
  /// row on screen rather than scrolling out of sight.
  void _syncHold() {
    final hold = widget.controller.text.isNotEmpty;
    if (hold == _holding) return;
    _holding = hold;
    _row?.hold(this, hold);
  }

  void _clear() {
    widget.controller.clear();
    widget.onChanged?.call('');
    widget.onClose?.call();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      textInputAction: TextInputAction.search,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search),
        hintText: widget.hint,
        isDense: true,
        suffixIcon: widget.controller.text.isEmpty && widget.onClose == null
            ? null
            : IconButton(
                icon: const Icon(Icons.close),
                tooltip: widget.clearTooltip,
                onPressed: _clear,
              ),
      ),
    );
  }
}

/// A filter that is on, shown as a removable chip in [FilterBar]'s line so
/// clearing it is one tap.
@immutable
class ActiveFilter {
  const ActiveFilter({
    required this.label,
    required this.onRemove,
    required this.removeTooltip,
  });

  final String label;
  final VoidCallback onRemove;

  /// The delete button's tooltip, e.g. "Remove filter: 5K".
  final String removeTooltip;
}

/// An on/off quick filter (Starred, Near me). On a chip line it is a
/// `FilterChip`; where it would be the only chip on a line of its own,
/// [FilterBar] draws it as a toggle icon button in the search row instead
/// ([asIconButton]), so a lone chip never spends a whole row (issue #1374).
///
/// Its state never rests on colour alone: the glyph swaps between [icon] and
/// [selectedIcon], and a screen reader hears it as a toggle that is on or off.
class FilterToggle extends StatelessWidget {
  const FilterToggle({
    super.key,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.selected,
    required this.onChanged,
    this.selectedColor,
  });

  /// The chip's text, and the icon button's tooltip and name.
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool selected;
  final ValueChanged<bool> onChanged;

  /// The glyph's colour while on. Defaults to the theme's primary.
  final Color? selectedColor;

  Color _glyphColor(ThemeData theme) => selected
      ? selectedColor ?? theme.colorScheme.primary
      : theme.colorScheme.onSurfaceVariant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FilterChip(
      label: Text(label),
      avatar: Icon(selected ? selectedIcon : icon,
          size: 18, color: _glyphColor(theme)),
      selected: selected,
      showCheckmark: false,
      onSelected: onChanged,
    );
  }

  /// The same toggle as an icon button, for the search row.
  Widget asIconButton(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      toggled: selected,
      label: label,
      excludeSemantics: true,
      onTap: () => onChanged(!selected),
      child: IconButton(
        key: const Key('filter-bar-toggle'),
        tooltip: label,
        isSelected: selected,
        icon: Icon(icon, color: _glyphColor(theme)),
        selectedIcon: Icon(selectedIcon, color: _glyphColor(theme)),
        onPressed: () => onChanged(!selected),
      ),
    );
  }
}

/// The control row of a list: at most one search field, at most one line of
/// quick chips that scrolls sideways and never wraps, and a Filters button
/// with the active count that opens the sheet holding everything else, whose
/// active filters show as removable chips on the same line.
///
/// The chips only filter; a chip that opened another screen would look like
/// a filter and navigate (issue #1374 report 2, rule 4).
///
/// The Filters button sits beside the search when there is one, and
/// otherwise leads the chip line inside its scroll.
///
/// No row holds a single control on its own (issue #1374, the owner's
/// Training and Social hub screenshots): a lone [FilterToggle] becomes a
/// toggle icon button in the search row, and with no search the [trailing]
/// actions stand at the end of the chip line, outside its scroll, rather
/// than taking a row above it. Two or more chips keep their own line, which
/// scrolls sideways and fades at an edge with more beyond it
/// ([EdgeFadeScroll]). That line runs to the screen edges, the gutter inside
/// its scroll, so a chip past the edge is cut by the screen rather than 16 dp
/// short of it and the last chip can scroll clear (decisions § 2610). A tab's
/// views ([views], a [ViewSwitch]) are a row of their own above everything
/// else, and a filter never joins them.
class FilterBar extends StatelessWidget {
  const FilterBar({
    super.key,
    this.search,
    this.views,
    this.trailing = const [],
    this.chips = const [],
    this.chipsLabel,
    this.activeFilters = const [],
    this.filtersLabel,
    this.filtersSemanticLabel,
    this.activeFilterCount = 0,
    this.onOpenFilters,
    this.padding = const EdgeInsets.fromLTRB(
        AppInsets.gutter, AppSpace.sm, AppInsets.gutter, AppSpace.xs),
    this.collapsibleSearch = false,
  }) : assert((filtersLabel == null) == (onOpenFilters == null),
            'filtersLabel and onOpenFilters must be provided together');

  /// Usually an [AppSearchField].
  final Widget? search;

  /// The tab's views (Routes' Mine · Explore), usually a [ViewSwitch]: they
  /// switch what the tab shows rather than filter it, so they are a row of
  /// their own above everything else.
  final Widget? views;

  /// Icon actions after the search: a sort menu, Import, the QR scan, the
  /// tab's overflow. With no search they stand at the end of the chip line,
  /// outside its scroll; only with neither a search nor a chip line do they
  /// take a row. Icon buttons, not labelled ones: a labelled button at 2x
  /// text left the chips no room.
  final List<Widget> trailing;

  /// Names the chip line as a group for a screen reader, e.g. "Filter plans
  /// by status".
  final String? chipsLabel;

  /// The screen's most-used filter, as chips. [buildChoiceChip] lays a
  /// single-select set out the way `ChoiceChipRow` does.
  final List<Widget> chips;

  final List<ActiveFilter> activeFilters;

  /// The Filters button's text, shown with a badge carrying
  /// [activeFilterCount].
  final String? filtersLabel;

  /// What a screen reader hears for the Filters button, e.g. "Filters, 2
  /// active". Falls back to [filtersLabel].
  final String? filtersSemanticLabel;
  final int activeFilterCount;
  final VoidCallback? onOpenFilters;
  final EdgeInsets padding;

  /// Folds an [AppSearchField] [search] into a search icon at the end of the
  /// chip line, beside Filters, so the bar is one row: the icon opens the
  /// field in the line's place (focused, keyboard up), and the field's clear
  /// button empties it and closes it back to the chips. A field with a query
  /// stays open, so a live search is never folded out of sight. For a list
  /// under a map, where the map is the subject and the search a way in
  /// (Routes → Explore, decisions § 2610); the icon is named by the field's
  /// hint. Without a chip line there is nothing to fold beside, and the field
  /// stays a row of its own.
  final bool collapsibleSearch;

  /// This bar with [extra] appended to its [trailing], for a host that adds
  /// its own actions to the row.
  FilterBar withTrailing(List<Widget> extra) => extra.isEmpty
      ? this
      : FilterBar(
          key: key,
          search: search,
          views: views,
          trailing: [...trailing, ...extra],
          chips: chips,
          chipsLabel: chipsLabel,
          activeFilters: activeFilters,
          filtersLabel: filtersLabel,
          filtersSemanticLabel: filtersSemanticLabel,
          activeFilterCount: activeFilterCount,
          onOpenFilters: onOpenFilters,
          padding: padding,
          collapsibleSearch: collapsibleSearch,
        );

  /// An icon button carrying the count as a badge, named by its tooltip and
  /// its semantics label. Icon-only so it never squeezes the search: as a
  /// labelled button it took 177 dp at 1.3x text and pushed the row past a
  /// 360 dp screen.
  Widget _filtersButton() => Semantics(
        button: true,
        label: filtersSemanticLabel ?? filtersLabel,
        excludeSemantics: true,
        child: IconButton(
          key: const Key('filter-bar-filters'),
          tooltip: filtersLabel,
          onPressed: onOpenFilters,
          isSelected: activeFilterCount > 0,
          icon: Badge(
            isLabelVisible: activeFilterCount > 0,
            label: Text('$activeFilterCount'),
            child: const Icon(Icons.tune),
          ),
        ),
      );

  /// The bar with its search folded into the chip line ([collapsibleSearch]):
  /// the views, if any, then one row of the chips (scrolling, to the screen's
  /// start edge) and, pinned at its end, search, Filters and [trailing].
  Widget _collapsible(BuildContext context, AppSearchField field) {
    final start = padding.left;
    final end = padding.right;
    final line = EdgeFadeScroll(
      scrollKey: const Key('filter-bar-chips'),
      padding: EdgeInsetsDirectional.only(start: start),
      child: Row(
        children: [
          for (final chip in chips)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: AppSpace.sm),
              child: chip,
            ),
          for (final f in activeFilters)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: AppSpace.sm),
              child: InputChip(
                label: Text(f.label),
                selected: true,
                showCheckmark: false,
                onPressed: onOpenFilters,
                onDeleted: f.onRemove,
                deleteButtonTooltipMessage: f.removeTooltip,
                materialTapTargetSize: MaterialTapTargetSize.padded,
              ),
            ),
        ],
      ),
    );
    final Widget labelledLine = chipsLabel == null
        ? line
        // semantics-children: a group name, read once before the controls inside it
        : Semantics(container: true, label: chipsLabel, child: line);
    return Padding(
      padding: EdgeInsets.only(top: padding.top, bottom: padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (views case final views?) ...[
            Padding(
              padding: EdgeInsetsDirectional.only(start: start, end: end),
              child: views,
            ),
            const SizedBox(height: AppSpace.sm),
          ],
          _FoldedSearchRow(
            field: field,
            line: labelledLine,
            pinned: [
              if (onOpenFilters != null) _filtersButton(),
              ...trailing,
            ],
            start: start,
            end: end,
          ),
        ],
      ),
    );
  }

  /// Where the bar puts a single quick chip, so it never sits alone on a
  /// line: the search row as an icon button when it is a [FilterToggle] and
  /// that row exists, else its line. Never the view row: a filter is not a
  /// view.
  static LoneChipPlacement loneChipPlacement({
    required int chipCount,
    required bool isToggle,
    required bool hasTopRow,
    required bool filtersOnLine,
  }) {
    if (chipCount != 1 || filtersOnLine) return LoneChipPlacement.line;
    if (isToggle && hasTopRow) return LoneChipPlacement.searchRow;
    return LoneChipPlacement.line;
  }

  /// Whether the [trailing] actions stand at the chip line's end rather than
  /// in a row of their own: with no search, whenever there is a line.
  static bool trailingOnLine({
    required bool hasSearch,
    required bool hasTrailing,
    required bool hasLine,
  }) =>
      !hasSearch && hasTrailing && hasLine;

  @override
  Widget build(BuildContext context) {
    final field = search;
    if (collapsibleSearch &&
        field is AppSearchField &&
        (chips.isNotEmpty || activeFilters.isNotEmpty)) {
      return _collapsible(context, field);
    }
    final hasFilters = onOpenFilters != null;
    final filtersBesideSearch = hasFilters && search != null;
    final filtersOnLine = hasFilters && !filtersBesideSearch;
    final placement = loneChipPlacement(
      chipCount: chips.length,
      isToggle: chips.length == 1 && chips.single is FilterToggle,
      hasTopRow: search != null || trailing.isNotEmpty,
      filtersOnLine: filtersOnLine,
    );
    final lineChips =
        placement == LoneChipPlacement.line ? chips : const <Widget>[];
    final hasLine =
        filtersOnLine || lineChips.isNotEmpty || activeFilters.isNotEmpty;
    final actionsOnLine = trailingOnLine(
        hasSearch: search != null,
        hasTrailing: trailing.isNotEmpty,
        hasLine: hasLine);
    final hasTop = search != null ||
        (trailing.isNotEmpty && !actionsOnLine) ||
        placement == LoneChipPlacement.searchRow;
    Widget spaced(Widget child) => Padding(
          padding: const EdgeInsetsDirectional.only(end: AppSpace.sm),
          child: child,
        );
    final start = padding.left;
    final end = padding.right;
    Widget gutters(Widget row) => Padding(
          padding: EdgeInsetsDirectional.only(start: start, end: end),
          child: row,
        );
    final line = EdgeFadeScroll(
      scrollKey: const Key('filter-bar-chips'),
      // With the actions at its end, the line stops at them, so only its
      // start runs to the edge.
      padding: EdgeInsetsDirectional.only(
          start: start, end: actionsOnLine ? 0 : end),
      child: Row(
        children: [
          if (filtersOnLine) spaced(_filtersButton()),
          for (final chip in lineChips) spaced(chip),
          for (final f in activeFilters)
            spaced(InputChip(
              label: Text(f.label),
              selected: true,
              showCheckmark: false,
              onPressed: onOpenFilters,
              onDeleted: f.onRemove,
              deleteButtonTooltipMessage: f.removeTooltip,
              materialTapTargetSize: MaterialTapTargetSize.padded,
            )),
        ],
      ),
    );
    final Widget labelledLine = chipsLabel == null
        ? line
        // semantics-children: a group name, read once before the controls inside it
        : Semantics(container: true, label: chipsLabel, child: line);
    final rows = <Widget>[
      if (views case final views?) gutters(views),
      if (hasTop)
        gutters(Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (search case final search?) Expanded(child: search),
            if (placement == LoneChipPlacement.searchRow)
              (chips.single as FilterToggle).asIconButton(context),
            if (filtersBesideSearch) _filtersButton(),
            if (!actionsOnLine) ...trailing,
          ],
        )),
      if (hasLine)
        actionsOnLine
            ? Padding(
                padding: EdgeInsetsDirectional.only(end: end),
                child: Row(
                  key: const Key('filter-bar-line-actions'),
                  children: [Expanded(child: labelledLine), ...trailing],
                ),
              )
            : labelledLine,
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: padding.top, bottom: padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpace.sm),
            rows[i],
          ],
        ],
      ),
    );
  }
}

/// [FilterBar]'s chip line with its search folded into an icon: the line
/// and the icon, or the open field in the line's place. It owns whether the
/// field is open, so the bar can stay a plain widget its host rebuilds.
class _FoldedSearchRow extends StatefulWidget {
  const _FoldedSearchRow({
    required this.field,
    required this.line,
    required this.pinned,
    required this.start,
    required this.end,
  });

  final AppSearchField field;
  final Widget line;

  /// Filters and the host's actions, at the row's end either way.
  final List<Widget> pinned;
  final double start;
  final double end;

  @override
  State<_FoldedSearchRow> createState() => _FoldedSearchRowState();
}

class _FoldedSearchRowState extends State<_FoldedSearchRow> {
  bool _open = false;
  final _fieldFocus = FocusNode(debugLabel: 'filter-bar-search-field');
  final _iconFocus = FocusNode(debugLabel: 'filter-bar-search-icon');

  TextEditingController get _text => widget.field.controller;

  /// Open while asked, and always while there is a query to show.
  bool get _shown => _open || _text.text.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _text.addListener(_onText);
  }

  @override
  void didUpdateWidget(_FoldedSearchRow old) {
    super.didUpdateWidget(old);
    if (old.field.controller != _text) {
      old.field.controller.removeListener(_onText);
      _text.addListener(_onText);
    }
  }

  @override
  void dispose() {
    _text.removeListener(_onText);
    _fieldFocus.dispose();
    _iconFocus.dispose();
    super.dispose();
  }

  void _onText() {
    if (mounted) setState(() {});
  }

  void _openField() {
    setState(() => _open = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) (widget.field.focusNode ?? _fieldFocus).requestFocus();
    });
  }

  /// The field's clear has already emptied it; closing hands focus back to
  /// the icon, so a screen reader lands where it came from.
  void _close() {
    setState(() => _open = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _iconFocus.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    return Padding(
      padding: EdgeInsetsDirectional.only(
          start: shown ? widget.start : 0, end: widget.end),
      child: Row(
        children: [
          Expanded(
            child: shown
                ? widget.field.opened(onClose: _close, focusNode: _fieldFocus)
                : widget.line,
          ),
          if (!shown)
            IconButton(
              key: const Key('filter-bar-search'),
              focusNode: _iconFocus,
              tooltip: widget.field.hint,
              icon: const Icon(Icons.search),
              onPressed: _openField,
            ),
          ...widget.pinned,
        ],
      ),
    );
  }
}

/// Where [FilterBar] puts a single quick chip.
enum LoneChipPlacement {
  /// On the chip line, with the Filters button or active filters beside it,
  /// or as the bar's only row.
  line,

  /// As a toggle icon button in the search row.
  searchRow,
}

/// Opens the sheet behind [FilterBar]'s Filters button: a title, the filter
/// controls (which may wrap here, unlike the bar's line), and Done pinned
/// below them, with an optional Reset beside it. Built on [SheetScaffold], so
/// Done clears the keyboard and the nav bar.
///
/// [builder] gets a setter that rebuilds the sheet; changes are meant to
/// apply at once, so the list behind it is already right when it closes.
Future<void> showFilterSheet({
  required BuildContext context,
  required String title,
  required String doneLabel,
  required Widget Function(BuildContext context, StateSetter setSheet) builder,
  String? resetLabel,
  VoidCallback? onReset,
}) {
  assert((resetLabel == null) == (onReset == null),
      'resetLabel and onReset must be provided together');
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheet) => SheetScaffold(
        title: Text(title),
        actions: Row(
          children: [
            if (onReset != null)
              TextButton(
                onPressed: () {
                  onReset();
                  setSheet(() {});
                },
                child: Text(resetLabel!),
              ),
            const Spacer(),
            FilledButton(
              key: const Key('filter-sheet-done'),
              onPressed: () => Navigator.of(sheetContext).pop(),
              child: Text(doneLabel),
            ),
          ],
        ),
        body: builder(sheetContext, setSheet),
      ),
    ),
  );
}
