import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart'
    show
        AppInsets,
        AppSearchField,
        AppSpace,
        EmptyState,
        ListCard,
        PageHeader,
        PushedPage,
        SheetScaffold;

import '../catalogue_browse.dart' show fold;
import '../explore_viewport.dart' show ExplorePin, ExploreSort;
import '../fab_clearance.dart';
import '../l10n/gen/app_localizations.dart';
import '../routes_views.dart';

/// The pieces Explore routes, Explore segments and Mine share (decisions
/// § 2611): one menu for the three views, the bar that floats on a map's top
/// edge, the List pill, the card a tapped route opens, the empty-view note,
/// "Which route?", the search sheet and the roomier list card.

String routesShowLabel(AppLocalizations l10n, RoutesShow show) =>
    switch (show) {
      RoutesShow.mine => l10n.exploreMapViewMine,
      RoutesShow.routes => l10n.exploreMapViewRoutes,
      RoutesShow.segments => l10n.exploreMapViewSegments,
    };

/// One button naming the view on screen; it opens My routes, Explore routes
/// and Explore segments. It replaced the `Mine · Explore` switch and the
/// `Routes · Segments` chips, two rows the map paid for.
class RoutesViewMenu extends StatelessWidget {
  const RoutesViewMenu({
    super.key,
    required this.show,
    required this.onSelected,
    this.floating = false,
  });

  final RoutesShow show;
  final ValueChanged<RoutesShow> onSelected;

  /// Raised over a map rather than sitting in a control row.
  final bool floating;

  static IconData _icon(RoutesShow v) => switch (v) {
    RoutesShow.mine => Icons.bookmarks_outlined,
    RoutesShow.routes => Icons.route,
    RoutesShow.segments => Icons.timeline,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final label = routesShowLabel(l10n, show);
    return PopupMenuButton<RoutesShow>(
      key: const ValueKey('routes-view-menu'),
      tooltip: l10n.exploreMapViewMenuLabel(label),
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final v in RoutesShow.values)
          PopupMenuItem<RoutesShow>(
            key: ValueKey('routes-view-menu-${v.name}'),
            value: v,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(_icon(v)),
              title: Text(routesShowLabel(l10n, v)),
              trailing: v == show ? const Icon(Icons.check) : null,
            ),
          ),
      ],
      child: Material(
        color: theme.colorScheme.surface,
        elevation: floating ? 2 : 0,
        shape: StadiumBorder(
          side: floating
              ? BorderSide.none
              : BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpace.md,
              AppSpace.xs,
              AppSpace.sm,
              AppSpace.xs,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpace.xs),
                const Icon(Icons.expand_more),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A round 48 dp button on a map's top edge, named by [label] for a screen
/// reader and a long press. [count] badges the filters that are on.
class ExploreRoundButton extends StatelessWidget {
  const ExploreRoundButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.count = 0,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: label,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 2,
        shadowColor: scheme.shadow,
        minimumSize: const Size.square(48),
      ),
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        child: Icon(icon),
      ),
    );
  }
}

/// The bar that floats on a map's top edge: the view menu, then Search and
/// Filters.
class ExploreTopBar extends StatelessWidget {
  const ExploreTopBar({
    super.key,
    required this.menu,
    required this.searchLabel,
    required this.onSearch,
    required this.filtersLabel,
    required this.onFilters,
    this.filterCount = 0,
  });

  final Widget menu;
  final String searchLabel;
  final VoidCallback onSearch;
  final String filtersLabel;
  final VoidCallback onFilters;
  final int filterCount;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppInsets.gutter,
      AppSpace.sm,
      AppInsets.gutter,
      0,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Align(alignment: AlignmentDirectional.topStart, child: menu),
        ),
        const SizedBox(width: AppSpace.xs),
        ExploreRoundButton(
          key: const ValueKey('explore-search'),
          icon: Icons.search,
          label: searchLabel,
          onPressed: onSearch,
        ),
        ExploreRoundButton(
          key: const ValueKey('explore-filters'),
          icon: Icons.tune,
          label: filtersLabel,
          count: filterCount,
          onPressed: onFilters,
        ),
      ],
    ),
  );
}

/// "List · 12 routes", centred at the map's foot: the routes in view as a
/// page of their own.
class ExploreListPill extends StatelessWidget {
  const ExploreListPill({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Center(
    child: FilledButton.icon(
      key: const ValueKey('explore-list-pill'),
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        elevation: 3,
        shape: const StadiumBorder(),
      ),
      icon: const Icon(Icons.list),
      label: Text(label, textAlign: TextAlign.center),
    ),
  );
}

/// What a map with nothing in view says instead of nothing at all, with the
/// ways back to something.
class ExploreEmptyOverlay extends StatelessWidget {
  const ExploreEmptyOverlay({
    super.key,
    required this.title,
    required this.onZoomOut,
    this.nearestName,
    this.onNearest,
    this.onClearFilters,
  });

  final String title;
  final VoidCallback onZoomOut;
  final String? nearestName;
  final VoidCallback? onNearest;
  final VoidCallback? onClearFilters;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppInsets.gutter,
        vertical: AppSpace.sm,
      ),
      child: Center(
        child: Material(
          key: const ValueKey('explore-empty-view'),
          color: theme.colorScheme.surface,
          elevation: 2,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpace.sm),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.xs,
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('explore-zoom-out'),
                      onPressed: onZoomOut,
                      icon: const Icon(Icons.zoom_out),
                      label: Text(l10n.exploreMapZoomOut),
                    ),
                    if (onClearFilters case final clear?)
                      OutlinedButton(
                        onPressed: clear,
                        child: Text(l10n.routesClearFilters),
                      ),
                    if ((nearestName, onNearest) case (
                      final String name,
                      final VoidCallback go,
                    ))
                      OutlinedButton(
                        key: const ValueKey('explore-nearest'),
                        onPressed: go,
                        child: Text(
                          l10n.exploreMapNearest(name),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The card a tapped route or segment opens over the map's foot: the whole
/// name, wrapping, an "Official course" line under it rather than a badge on
/// the title line, one stats line, then the actions. Close returns to the
/// plain map.
class ExploreSelectedCard extends StatelessWidget {
  const ExploreSelectedCard({
    super.key,
    required this.name,
    required this.stats,
    required this.actions,
    required this.onClose,
    this.official = false,
    this.detail,
  });

  final String name;
  final bool official;
  final String? detail;
  final String stats;
  final List<Widget> actions;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Material(
      color: theme.colorScheme.surface,
      elevation: 4,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpace.md,
          AppSpace.sm,
          AppSpace.xs,
          AppSpace.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: AppSpace.sm),
                    child: Semantics(
                      header: true,
                      child: Text(
                        name,
                        key: const ValueKey('explore-card-name'),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('explore-card-close'),
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: onClose,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: AppSpace.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (official)
                    ExploreOfficialLine(label: l10n.exploreMapOfficialCourse),
                  if (detail case final d? when d.trim().isNotEmpty)
                    Text(d, style: muted),
                  Text(stats, style: muted),
                  const SizedBox(height: AppSpace.smPlus),
                  Wrap(
                    spacing: AppSpace.sm,
                    runSpacing: AppSpace.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: actions,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Official course", with its mark, on a line of its own under a name.
class ExploreOfficialLine extends StatelessWidget {
  const ExploreOfficialLine({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text.rich(
        TextSpan(
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: 4),
                child: Icon(Icons.verified, size: 16, color: color),
              ),
            ),
            TextSpan(text: label),
          ],
        ),
        style: theme.textTheme.bodyMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// One row of a list of routes or segments: a 76 dp shape on the left, the
/// whole name, the Official line and the stats on the right. Mine passes its
/// own [trailing] actions and selection.
class ExploreListCard extends StatelessWidget {
  const ExploreListCard({
    super.key,
    required this.name,
    required this.stats,
    required this.thumbnail,
    required this.onTap,
    this.official = false,
    this.detail,
    this.badge,
    this.trailing,
    this.onLongPress,
    this.selecting = false,
    this.selected = false,
  });

  static const double thumbnailSize = 76;

  final String name;
  final bool official;
  final String? detail;
  final String stats;
  final Widget thumbnail;
  final VoidCallback onTap;
  final Widget? badge;
  final Widget? trailing;
  final VoidCallback? onLongPress;
  final bool selecting;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return ListCard.row(
      margin: EdgeInsets.zero,
      dense: true,
      onTap: onTap,
      onLongPress: onLongPress,
      selecting: selecting,
      selected: selected,
      leadingWidth: thumbnailSize,
      leading: SizedBox.square(
        dimension: thumbnailSize,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ColoredBox(
            color: theme.colorScheme.surfaceContainerHighest,
            child: thumbnail,
          ),
        ),
      ),
      title: name,
      titleMaxLines: 99,
      badge: badge,
      meta: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (official)
            ExploreOfficialLine(label: l10n.exploreMapOfficialCourse),
          if (detail case final d? when d.trim().isNotEmpty)
            Text(d, style: muted),
          Text(stats, style: muted),
        ],
      ),
      trailing: trailing,
    );
  }
}

/// "Which route?": a tap that landed on several overlapping routes lists
/// them by name instead of opening whichever was drawn on top. Resolves to
/// the chosen id.
Future<String?> showExplorePicker(
  BuildContext context, {
  required String title,
  required List<({String id, String name, String stats})> items,
}) {
  return showModalBottomSheet<String>(
    context: context,
    builder: (sheetContext) => SheetScaffold(
      title: Text(title),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final item in items)
            ListTile(
              key: ValueKey('explore-picker-${item.id}'),
              contentPadding: EdgeInsets.zero,
              title: Text(item.name),
              subtitle: Text(item.stats),
              onTap: () => Navigator.of(sheetContext).pop(item.id),
            ),
        ],
      ),
    ),
  );
}

/// One match in [showExploreSearch]'s list.
typedef ExploreSearchHit = ({String id, String name, String meta});

/// A tall sheet with a search field and its matches, for finding a route or
/// segment anywhere rather than only in view. [search] runs a short pause
/// after the last keystroke. Resolves to the chosen id.
Future<String?> showExploreSearch(
  BuildContext context, {
  required String hint,
  required Future<List<ExploreSearchHit>> Function(String query) search,
  required String emptyText,
  required String failedText,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ExploreSearchSheet(
      hint: hint,
      search: search,
      emptyText: emptyText,
      failedText: failedText,
    ),
  );
}

class _ExploreSearchSheet extends StatefulWidget {
  const _ExploreSearchSheet({
    required this.hint,
    required this.search,
    required this.emptyText,
    required this.failedText,
  });

  final String hint;
  final Future<List<ExploreSearchHit>> Function(String query) search;
  final String emptyText;
  final String failedText;

  @override
  State<_ExploreSearchSheet> createState() => _ExploreSearchSheetState();
}

class _ExploreSearchSheetState extends State<_ExploreSearchSheet> {
  final _controller = TextEditingController();
  Timer? _typing;
  List<ExploreSearchHit> _hits = const [];
  bool _busy = false;
  bool _failed = false;
  String _query = '';
  int _reads = 0;

  @override
  void dispose() {
    _typing?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _typing?.cancel();
    _typing = Timer(const Duration(milliseconds: 400), () => _run(text));
  }

  Future<void> _run(String text) async {
    final q = text.trim();
    final read = ++_reads;
    if (q.isEmpty) {
      setState(() {
        _query = '';
        _hits = const [];
        _failed = false;
        _busy = false;
      });
      return;
    }
    setState(() {
      _query = q;
      _busy = true;
    });
    try {
      final hits = await widget.search(q);
      if (!mounted || read != _reads) return;
      setState(() {
        _hits = hits;
        _failed = false;
        _busy = false;
      });
    } catch (e) {
      debugPrint('explore search failed: $e');
      if (!mounted || read != _reads) return;
      setState(() {
        _failed = true;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return SheetScaffold.expanding(
      pinned: AppSearchField(
        key: const ValueKey('explore-search-field'),
        controller: _controller,
        hint: widget.hint,
        clearTooltip: l10n.commonClearSearch,
        autofocus: true,
        onChanged: _onChanged,
        onSubmitted: _run,
      ),
      slivers: [
        if (_busy)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(AppSpace.md),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          ),
        if (!_busy && _failed)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.md),
              child: Text(widget.failedText, style: theme.textTheme.bodyMedium),
            ),
          )
        else if (!_busy && _query.isNotEmpty && _hits.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.md),
              child: Text(widget.emptyText, style: theme.textTheme.bodyMedium),
            ),
          ),
        SliverList.builder(
          itemCount: _hits.length,
          itemBuilder: (context, i) {
            final hit = _hits[i];
            return ListTile(
              key: ValueKey('explore-search-hit-${hit.id}'),
              title: Text(hit.name),
              subtitle: hit.meta.isEmpty ? null : Text(hit.meta),
              onTap: () => Navigator.of(context).pop(hit.id),
            );
          },
        ),
      ],
    );
  }
}

/// The sort chip's choices on a list of routes in view.
String exploreSortLabel(AppLocalizations l10n, ExploreSort sort) =>
    switch (sort) {
      ExploreSort.nearest => l10n.exploreMapSortNearest,
      ExploreSort.mostRun => l10n.exploreRoutesSortMostRun,
      ExploreSort.name => l10n.exploreMapSortName,
    };

/// The "on the map" list as a page of its own (decisions § 2611): what is in
/// the map's view, with a sort chip, Filters and a search that narrows it by
/// name. It rebuilds when [changes] fires, so a filter set here is the
/// filter the map shows on return. A card resolves the page to its id, and
/// the map opens on it.
class ExploreListPage<T extends ExplorePin> extends StatefulWidget {
  const ExploreListPage({
    super.key,
    required this.title,
    required this.changes,
    required this.items,
    required this.sorts,
    required this.sortLabel,
    required this.initialSort,
    required this.sortBy,
    required this.cardBuilder,
    required this.onOpenFilters,
    required this.filterCount,
    required this.searchHint,
    required this.emptyText,
  });

  final String title;
  final Listenable changes;
  final List<T> Function() items;
  final List<Object> Function() sorts;
  final String Function(Object sort) sortLabel;
  final Object initialSort;
  final List<T> Function(List<T> items, Object sort) sortBy;
  final Widget Function(BuildContext context, T item, VoidCallback onTap)
  cardBuilder;
  final Future<void> Function(BuildContext context) onOpenFilters;
  final int Function() filterCount;
  final String searchHint;
  final String emptyText;

  @override
  State<ExploreListPage<T>> createState() => _ExploreListPageState<T>();
}

class _ExploreListPageState<T extends ExplorePin>
    extends State<ExploreListPage<T>> {
  final _search = TextEditingController();
  late Object _sort = widget.initialSort;

  @override
  void initState() {
    super.initState();
    widget.changes.addListener(_changed);
  }

  @override
  void dispose() {
    widget.changes.removeListener(_changed);
    _search.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sorts = widget.sorts();
    if (!sorts.contains(_sort)) _sort = sorts.first;
    final q = fold(_search.text.trim());
    final all = widget.items();
    final narrowed = q.isEmpty
        ? all
        : [
            for (final p in all)
              if (fold(p.name).contains(q)) p,
          ];
    final listed = widget.sortBy(narrowed, _sort);
    final filters = widget.filterCount();
    return PushedPage(
      title: widget.title,
      body: ListView(
        key: const ValueKey('explore-list-page'),
        padding: EdgeInsets.fromLTRB(
          AppInsets.gutter,
          0,
          AppInsets.gutter,
          listEndClearance(context),
        ),
        children: [
          PageHeader(
            title: widget.title,
            padding: const EdgeInsets.only(
              top: AppSpace.md,
              bottom: AppSpace.sm,
            ),
          ),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              PopupMenuButton<Object>(
                key: const ValueKey('explore-list-sort'),
                tooltip: l10n.exploreMapSortLabel,
                onSelected: (v) => setState(() => _sort = v),
                itemBuilder: (_) => [
                  for (final s in sorts)
                    CheckedPopupMenuItem<Object>(
                      value: s,
                      checked: s == _sort,
                      child: Text(widget.sortLabel(s)),
                    ),
                ],
                child: Chip(
                  avatar: const Icon(Icons.sort, size: 18),
                  label: Text(widget.sortLabel(_sort)),
                ),
              ),
              ActionChip(
                key: const ValueKey('explore-list-filters'),
                avatar: const Icon(Icons.tune, size: 18),
                label: Text(
                  filters > 0
                      ? l10n.filterBarFiltersCount(filters)
                      : l10n.filterBarFilters,
                ),
                onPressed: () => widget.onOpenFilters(context),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          AppSearchField(
            controller: _search,
            hint: widget.searchHint,
            clearTooltip: l10n.commonClearSearch,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpace.sm),
          if (listed.isEmpty)
            EmptyState(icon: Icons.explore, title: widget.emptyText)
          else
            for (final item in listed) ...[
              widget.cardBuilder(
                context,
                item,
                () => Navigator.of(context).pop(item.id),
              ),
              const SizedBox(height: AppInsets.itemGap),
            ],
        ],
      ),
    );
  }
}
