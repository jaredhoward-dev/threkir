import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../local_run_store.dart';
import '../offline_sync_store.dart';

/// Persistent disclosure for offline-store rows that haven't reached the
/// server. Rendered as a function of the stores' pending state, NOT of
/// connectivity: a push rejected while online (RLS denial, 500, expired
/// token, timeout) leaves the row pending with the device online, and the
/// old `_isOnline`-gated banners showed nothing for exactly that case
/// (issue #666 U2). Mirrors the runs surface's always-on unsynced badge.
///
/// Renders nothing when nothing is pending. Pending while offline shows the
/// "saved on this device" copy; pending while a push is in flight shows
/// "Syncing…"; pending while online otherwise means a push failed, so the
/// copy says so and offers a Retry wired to [OfflineSyncStore.syncWithServer]
/// on every store that still has rows.
///
/// Runs are not an [OfflineSyncStore] — their queue is [LocalRunStore] and
/// their drain is `SyncService` — so they come in through [runStore] and
/// [onRetryRuns]. Unsynced runs count with everything else pending; a parked
/// run gets its own line, because retrying will not move it.
class PendingSyncBanner extends StatefulWidget {
  final ApiClient? api;
  final bool isOnline;
  final List<OfflineSyncStore<SyncEntry>> stores;
  final LocalRunStore? runStore;
  final Future<void> Function()? onRetryRuns;

  /// True while the run sync is pushing (`SyncService.syncing`). Pending rows
  /// read "Syncing…" rather than as a failure while it is.
  final ValueListenable<bool>? runsSyncing;

  /// Space around the banner, applied only while it shows, so a host can
  /// separate it from the next card without leaving a gap when it is hidden.
  final EdgeInsetsGeometry margin;

  const PendingSyncBanner({
    super.key,
    required this.api,
    required this.isOnline,
    required this.stores,
    this.runStore,
    this.onRetryRuns,
    this.runsSyncing,
    this.margin = EdgeInsets.zero,
  });

  @override
  State<PendingSyncBanner> createState() => _PendingSyncBannerState();
}

class _PendingSyncBannerState extends State<PendingSyncBanner> {
  bool _retrying = false;

  Future<void> _retry() async {
    final api = widget.api;
    if (api == null || _retrying) return;
    setState(() => _retrying = true);
    try {
      for (final store in widget.stores) {
        if (store.hasPending) await store.syncWithServer(api);
      }
      final runs = widget.runStore;
      final retryRuns = widget.onRetryRuns;
      if (runs != null && retryRuns != null && runs.unsyncedCount > 0) {
        await retryRuns();
      }
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final syncing = widget.runsSyncing;
    return ListenableBuilder(
      listenable: Listenable.merge([
        ...widget.stores,
        if (widget.runStore != null) widget.runStore!,
        if (syncing != null) syncing,
      ]),
      builder: (context, _) {
        var pending = widget.runStore?.unsyncedCount ?? 0;
        for (final s in widget.stores) {
          pending += s.pendingCount;
        }
        final parked = widget.runStore?.blockedCount ?? 0;
        if (pending == 0 && parked == 0) return const SizedBox.shrink();
        final theme = Theme.of(context);
        final l10n = AppLocalizations.of(context);
        final online = widget.isOnline && widget.api?.userId != null;
        // An upload in flight is not a failure: an added past run is pushed
        // the moment it is saved, and calling it "hasn't synced" for that
        // second read as an error the runner had just caused.
        final inFlight = online && (_retrying || (syncing?.value ?? false));
        final canRetry = pending > 0 && online && !inFlight;
        return Padding(
          padding: widget.margin,
          child: Material(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: canRetry ? _retry : null,
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 4, 4),
                // The action is a fixed-width icon, not a `TextButton`: a text
                // label takes its intrinsic width first, so a long German /
                // French "Retry" starved the `Expanded` message down to a few
                // pixels (decisions § 486, § 488). The whole banner is the tap
                // target too.
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (pending > 0)
                                _line(
                                  theme,
                                  icon: inFlight
                                      ? Icons.sync
                                      : online
                                      ? Icons.sync_problem
                                      : Icons.cloud_off,
                                  text: inFlight
                                      ? l10n.runSyncing
                                      : online
                                      ? l10n.pendingSyncFailed(pending)
                                      : l10n.pendingSyncOffline(pending),
                                ),
                              if (pending > 0 && parked > 0)
                                const SizedBox(height: 6),
                              if (parked > 0)
                                _line(
                                  theme,
                                  icon: Icons.error_outline,
                                  color: theme.colorScheme.error,
                                  text: l10n.historySyncBlocked(parked),
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (inFlight && pending > 0)
                        const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else if (canRetry)
                        IconButton(
                          onPressed: _retry,
                          tooltip: l10n.pendingSyncRetry,
                          color: theme.colorScheme.primary,
                          icon: const Icon(Icons.refresh),
                        )
                      else
                        const SizedBox(width: 12),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _line(
    ThemeData theme, {
    required IconData icon,
    required String text,
    Color? color,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: color ?? theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
      ],
    );
  }
}
