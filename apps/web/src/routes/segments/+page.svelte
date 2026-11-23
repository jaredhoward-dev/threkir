<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/state';
	import { goto } from '$app/navigation';
	import { m } from '#lib/i18n/store.svelte.ts';
	import { errorCopy } from '#lib/i18n/error_copy.ts';
	import RunSurfaceTabs from '#lib/components/RunSurfaceTabs.svelte';
	import RoutesViewNav from '#lib/components/RoutesViewNav.svelte';
	import EmptyState from '#lib/components/EmptyState.svelte';
	import Modal from '#lib/components/Modal.svelte';
	import AppSearchField from '#lib/components/AppSearchField.svelte';
	import ExploreShell from '#lib/components/ExploreShell.svelte';
	import ExploreMap from '#lib/components/ExploreMap.svelte';
	import ExploreCard from '#lib/components/ExploreCard.svelte';
	import ExploreListCard from '#lib/components/ExploreListCard.svelte';
	import ExplorePicker from '#lib/components/ExplorePicker.svelte';
	import ExploreEmptyView from '#lib/components/ExploreEmptyView.svelte';
	import ExploreMapButton from '#lib/components/ExploreMapButton.svelte';
	import TrackPreview from '#lib/components/TrackPreview.svelte';
	import type { MessageKey } from '#lib/i18n/messages.ts';
	import { routeSurfaceLabel } from '#lib/i18n/enum_labels.svelte.ts';
	import { distanceInPreferred, formatElevation } from '#lib/format/units.svelte.ts';
	import { fetchGlobalSegmentsWithError, type GlobalSegment } from '#lib/core/data.ts';
	import {
		catalogueRegions,
		catalogueSurfaces,
		filterCatalogue,
		sortCatalogue,
		type CatalogueSort,
	} from '#lib/segments/catalogue_browse.ts';
	import { haversineMetres } from '#lib/geo/haversine.ts';
	import {
		inBounds,
		nearestTo,
		type ExploreLine,
		type ExplorePin,
		type LatLng,
		type ViewBounds,
	} from '#lib/routes/explore_viewport.ts';

	// Routes → Explore segments, map first like Explore routes (decisions
	// § 2611): every catalogue segment drawn on the map with its start pin, a
	// tapped one as a card, and the segments in view as a list of their own
	// (`?view=list`). The catalogue is world-readable and fetched whole, so the
	// view, the search and the filters cost no round-trip, and the page works
	// signed out.

	type ListSort = CatalogueSort | 'nearest';

	let segments = $state<GlobalSegment[]>([]);
	let loading = $state(true);
	let loadError = $state<string | null>(null);

	let query = $state('');
	let region = $state<string | null>(null);
	let surface = $state<string | null>(null);
	let sortChoice = $state<ListSort | null>(null);
	let filtersOpen = $state(false);

	let bounds = $state<ViewBounds | null>(null);
	let center = $state<LatLng | null>(null);
	let origin = $state<LatLng | null>(null);
	let mapRef: ReturnType<typeof ExploreMap> | undefined = $state();
	let framed = false;

	let selectedId = $state<string | null>(null);
	let pickIds = $state<string[] | null>(null);
	let searchOpen = $state(false);
	let mapQuery = $state('');
	let listFromMap = false;

	const listOpen = $derived(page.url.searchParams.get('view') === 'list');

	const SORTS: { value: CatalogueSort; key: MessageKey }[] = [
		{ value: 'name', key: 'segments.browseSortName' },
		{ value: 'shortest', key: 'segments.browseSortShortest' },
		{ value: 'longest', key: 'segments.browseSortLongest' },
		{ value: 'climb', key: 'segments.browseSortClimb' },
	];

	function startOf(s: GlobalSegment): LatLng | null {
		const p = s.waypoints[0];
		return p && Number.isFinite(p.lat) && Number.isFinite(p.lng) ? { lat: p.lat, lng: p.lng } : null;
	}

	const placed = $derived(segments.filter((s) => startOf(s) !== null));
	const regions = $derived(catalogueRegions(segments));
	const surfaces = $derived(catalogueSurfaces(segments));
	/// The catalogue helpers answer in their own row type; these map that answer
	/// back onto the full rows, in its order.
	function byIds(rows: readonly { id: string }[]): GlobalSegment[] {
		const byId = new Map(segments.map((s) => [s.id, s]));
		return rows.map((r) => byId.get(r.id)).filter((s): s is GlobalSegment => !!s);
	}
	const filtered = $derived(byIds(filterCatalogue(placed, { region, surface })));
	/// Until the map has a view (no consent yet, or not laid out), every
	/// segment counts as in view.
	const inView = $derived(
		bounds ? filtered.filter((s) => { const p = startOf(s)!; return inBounds(p.lat, p.lng, bounds!); }) : filtered,
	);
	const sort = $derived<ListSort>(sortChoice ?? (origin ? 'nearest' : 'name'));
	const listed = $derived.by(() => {
		const narrowed = byIds(filterCatalogue(inView, { query }));
		if (sort !== 'nearest' || !origin) return byIds(sortCatalogue(narrowed, sort === 'nearest' ? 'name' : sort));
		const o = origin;
		const d = (s: GlobalSegment) => {
			const p = startOf(s)!;
			return haversineMetres(o.lat, o.lng, p.lat, p.lng);
		};
		return byIds(sortCatalogue(narrowed, 'name')).sort((a, b) => d(a) - d(b));
	});
	const filterCount = $derived((region != null ? 1 : 0) + (surface != null ? 1 : 0));

	function pinOf(s: GlobalSegment): ExplorePin {
		const p = startOf(s)!;
		return {
			id: s.id,
			name: s.name,
			lat: p.lat,
			lng: p.lng,
			distanceM: Number(s.distance_m),
			surface: s.surface,
			featured: false,
			runCount: 0,
		};
	}
	const pins = $derived(filtered.map(pinOf));
	const lines = $derived<ExploreLine[]>(
		filtered.map((s) => ({ id: s.id, coords: s.waypoints.map((w) => [w.lng, w.lat] as [number, number]) })),
	);
	const selected = $derived(segments.find((s) => s.id === selectedId) ?? null);
	const pickItems = $derived(
		(pickIds ?? [])
			.map((id) => segments.find((s) => s.id === id))
			.filter((s): s is GlobalSegment => !!s)
			.map((s) => ({ id: s.id, name: s.name, stats: stats(s) })),
	);
	const mapMatches = $derived(mapQuery.trim() ? byIds(filterCatalogue(filtered, { query: mapQuery })).slice(0, 20) : []);
	const emptyView = $derived(!loading && bounds !== null && inView.length === 0 && !selected);
	const nearest = $derived.by(() => {
		if (!emptyView || !center) return null;
		return nearestTo(pins, center);
	});

	function fmtDist(metres: number | string): string {
		const { value, unit } = distanceInPreferred(Number(metres));
		return `${value.toFixed(2)} ${unit}`;
	}

	function stats(s: GlobalSegment): string {
		return [
			fmtDist(s.distance_m),
			s.elevation_m != null && Number(s.elevation_m) > 0 ? `${formatElevation(Number(s.elevation_m))} ↑` : null,
			routeSurfaceLabel(s.surface),
		]
			.filter(Boolean)
			.join(' · ');
	}

	async function load() {
		loading = true;
		loadError = null;
		try {
			const res = await fetchGlobalSegmentsWithError();
			if (res.error) {
				loadError = errorCopy(res.error, m, 'segments: loadError');
				return;
			}
			segments = res.segments;
		} catch (e) {
			// A rejected fetch must not read as "the catalogue is empty".
			loadError = errorCopy(e, m, 'segments: loadError');
		} finally {
			loading = false;
		}
	}

	onMount(load);

	function frameAll() {
		if (framed || !mapRef || placed.length === 0) return;
		framed = true;
		mapRef.fitLine(placed.map((s) => { const p = startOf(s)!; return [p.lng, p.lat] as [number, number]; }));
	}

	function onMove(b: ViewBounds, c: LatLng) {
		bounds = b;
		center = c;
		frameAll();
	}

	function select(id: string, frame = false) {
		selectedId = id;
		pickIds = null;
		searchOpen = false;
		const s = segments.find((x) => x.id === id);
		if (frame && s) mapRef?.fitLine(s.waypoints.map((w) => [w.lng, w.lat] as [number, number]));
	}

	function onPick(ids: string[]) {
		if (ids.length === 1) select(ids[0]);
		else if (ids.length > 1) pickIds = ids;
	}

	function backToMap() {
		if (listFromMap) {
			listFromMap = false;
			history.back();
		} else {
			void goto('/segments', { replace: true, reset: false });
		}
	}

	function locate() {
		navigator.geolocation?.getCurrentPosition(
			(pos) => {
				origin = { lat: pos.coords.latitude, lng: pos.coords.longitude };
				mapRef?.flyTo(origin, 11);
			},
			() => {},
			{ enableHighAccuracy: false, timeout: 10000, maximumAge: 60000 },
		);
	}

	function resetFilters() {
		query = '';
		region = null;
		surface = null;
		sortChoice = null;
	}

	function onKey(e: KeyboardEvent) {
		if (e.key !== 'Escape') return;
		if (pickIds) pickIds = null;
		else if (searchOpen) searchOpen = false;
		else if (selectedId) selectedId = null;
	}
</script>

<svelte:head><title>{m('segments.browseTitle')}</title></svelte:head>
<svelte:window onkeydown={onKey} />

<Modal open={filtersOpen} onclose={() => (filtersOpen = false)} title={m('filterBar.filters')} data-testid="segment-catalogue-filters-panel">
	<div class="editor-form sheet">
		{#if regions.length > 1}
			<label class="field">
				<span>{m('segments.browseRegion')}</span>
				<select bind:value={region} data-testid="segment-catalogue-region" aria-describedby="segment-filters-hint">
					<option value={null}>{m('segments.browseAllRegions')}</option>
					{#each regions as r (r)}
						<option value={r}>{r}</option>
					{/each}
				</select>
			</label>
		{/if}
		{#if surfaces.length > 1}
			<label class="field">
				<span>{m('segments.browseSurface')}</span>
				<select bind:value={surface} data-testid="segment-catalogue-surface" aria-describedby="segment-filters-hint">
					<option value={null}>{m('segments.browseAllSurfaces')}</option>
					{#each surfaces as s (s)}
						<option value={s}>{routeSurfaceLabel(s)}</option>
					{/each}
				</select>
			</label>
		{/if}
		<p class="filter-hint" id="segment-filters-hint">{m('segments.browseFiltersHint')}</p>
		<div class="sheet-actions">
			{#if filterCount > 0}
				<button type="button" class="btn btn-outline" onclick={resetFilters} data-testid="segment-catalogue-reset">
					{m('segments.reset')}
				</button>
			{/if}
			<button type="button" class="btn btn-primary" onclick={() => (filtersOpen = false)} data-testid="segment-catalogue-filters-done">
				{m('filterBar.done')}
			</button>
		</div>
	</div>
</Modal>

<!-- The search's and the sort's explanation, read on the controls that name
     it; the Filters sheet shows it as text. -->
<span class="visually-hidden" id="segment-search-desc">{m('segments.browseFiltersHint')}</span>

<div class="page">
	<!-- Routes → Explore → Segments (issue #1374, owner decision 1). -->
	<RunSurfaceTabs active="routes" />
	<RoutesViewNav view="segments" />

	{#if loading}
		<p class="state-msg">{m('segments.loadingSegments')}</p>
	{:else if loadError !== null}
		<div class="error-banner" role="alert" data-testid="segment-catalogue-error">
			<span class="material-symbols" aria-hidden="true">error</span>
			<div>
				<strong>{m('segments.browseFailed')}</strong>
				{#if loadError}<span class="error-detail">{loadError}</span>{/if}
			</div>
			<button type="button" class="btn btn-outline btn-sm" onclick={load}>
				{m('segmentDetail.retry')}
			</button>
		</div>
	{:else if segments.length === 0}
		<EmptyState icon="terrain" title={m('segments.browseEmpty')} data-testid="segment-catalogue-empty">
			{#snippet actions()}
				<a class="btn btn-outline" href="/races?show=courses">
					<span class="material-symbols" aria-hidden="true">park</span>
					{m('parks.browseLink')}
				</a>
			{/snippet}
		</EmptyState>
	{:else}
		<ExploreShell
			view="segments"
			{listOpen}
			listHref="/segments?view=list"
			listLabel={m('exploreMap.listSegments', { count: inView.length })}
			listTitle={m('exploreMap.listSegmentsTitle')}
			onbacktomap={backToMap}
			cardOpen={selected !== null}
			onopenlist={() => (listFromMap = true)}
		>
			{#snippet map()}
				<ExploreMap
					bind:this={mapRef}
					{pins}
					{lines}
					{selectedId}
					label={m('exploreMap.mapLabelSegments')}
					onmove={onMove}
					onpick={onPick}
					testid="explore-segments-map"
				/>
			{/snippet}

			{#snippet toolbar()}
				<ExploreMapButton round icon="search" label={m('segments.browseSearchPlaceholder')} onclick={() => (searchOpen = !searchOpen)} testid="explore-search-open" />
				<ExploreMapButton
					round
					icon="tune"
					label={filterCount > 0 ? m('filterBar.filtersCount', { count: filterCount }) : m('filterBar.filters')}
					count={filterCount}
					onclick={() => (filtersOpen = true)}
					testid="explore-filters-open"
				/>
			{/snippet}

			{#snippet mapButtons()}
				<ExploreMapButton href="/races?show=courses" icon="park" label={m('parks.browseLink')} testid="segments-parks-link" />
				<ExploreMapButton icon="near_me" label={m('discover.nearMe')} pressed={origin !== null} onclick={locate} testid="explore-near-me" />
			{/snippet}

			{#snippet overlay()}
				{#if searchOpen}
					<div class="search-panel" data-testid="explore-search-panel">
						<AppSearchField
							bind:value={mapQuery}
							label={m('segments.browseSearchLabel')}
							placeholder={m('segments.browseSearchPlaceholder')}
							testid="explore-search"
							describedby="segment-search-desc"
						/>
						{#if mapQuery.trim() && mapMatches.length === 0}
							<p class="search-note" role="status">{m('segments.browseNoMatches')}</p>
						{/if}
						<ul class="search-results">
							{#each mapMatches as s (s.id)}
								<li>
									<button type="button" onclick={() => select(s.id, true)} data-testid="explore-search-result">
										<span class="name">{s.name}</span>
										{#if s.region}<span class="meta">{s.region}</span>{/if}
									</button>
								</li>
							{/each}
						</ul>
					</div>
				{:else if pickIds}
					<ExplorePicker title={m('exploreMap.whichSegment')} items={pickItems} onpick={(id) => select(id)} onclose={() => (pickIds = null)} />
				{:else if emptyView}
					<ExploreEmptyView
						title={m('exploreMap.emptySegments')}
						onzoomout={() => mapRef?.zoomOut()}
						onclearfilters={filterCount > 0 ? resetFilters : undefined}
						nearest={nearest ? { name: nearest.name, onclick: () => { const n = nearest; if (n) select(n.id, true); } } : null}
					/>
				{/if}
			{/snippet}

			{#snippet card()}
				{#if selected}
					<ExploreCard name={selected.name} detail={selected.region} stats={stats(selected)} onclose={() => (selectedId = null)} testid="explore-segment-card">
						{#snippet actions()}
							<a class="btn btn-primary" href="/segments/{selected.id}" data-testid="explore-card-details">{m('exploreMap.details')}</a>
						{/snippet}
					</ExploreCard>
				{/if}
			{/snippet}

			{#snippet list()}
				<div class="list-controls">
					<label class="sort">
						<span>{m('exploreMap.sortLabel')}</span>
						<select
							value={sort}
							onchange={(e) => (sortChoice = (e.currentTarget as HTMLSelectElement).value as ListSort)}
							data-testid="segment-catalogue-sort"
							aria-describedby="segment-search-desc"
						>
							{#if origin}<option value="nearest">{m('exploreMap.sortNearest')}</option>{/if}
							{#each SORTS as option (option.value)}
								<option value={option.value}>{m(option.key)}</option>
							{/each}
						</select>
					</label>
					<button type="button" class="btn btn-outline btn-sm" onclick={() => (filtersOpen = true)} data-testid="segment-catalogue-filters-toggle">
						<span class="material-symbols" aria-hidden="true">tune</span>
						{filterCount > 0 ? m('filterBar.filtersCount', { count: filterCount }) : m('filterBar.filters')}
					</button>
				</div>
				<div class="list-search">
					<AppSearchField
						bind:value={query}
						label={m('segments.browseSearchLabel')}
						placeholder={m('segments.browseSearchPlaceholder')}
						testid="segment-catalogue-search"
						describedby="segment-search-desc"
					/>
				</div>
				<!-- One persistent live region whose contents swap, so emptying the
				     list is announced too. -->
				<div class="results-status" role="status">
					{#if listed.length === 0}
						<EmptyState
							icon="filter_alt_off"
							title={inView.length === 0 ? m('exploreMap.emptySegments') : m('segments.browseNoMatches')}
							data-testid="segment-catalogue-no-matches"
						>
							{#snippet actions()}
								{#if query || filterCount > 0}
									<button type="button" class="btn btn-primary" onclick={resetFilters}>{m('segments.clearFilters')}</button>
								{/if}
							{/snippet}
						</EmptyState>
					{:else}
						<p class="count" data-testid="segment-catalogue-count">{m('segments.browseCount', { count: listed.length })}</p>
					{/if}
				</div>
				{#if listed.length > 0}
					<ul class="cards" data-testid="segment-catalogue-list">
						{#each listed as s (s.id)}
							<li>
								<ExploreListCard
									name={s.name}
									detail={s.region}
									stats={stats(s)}
									onclick={() => {
										backToMap();
										select(s.id, true);
									}}
									testid="segment-card-{s.id}"
								>
									{#snippet thumbnail()}
										<TrackPreview points={s.waypoints} />
									{/snippet}
								</ExploreListCard>
							</li>
						{/each}
					</ul>
				{/if}
			{/snippet}
		</ExploreShell>
	{/if}
</div>

<style>
	.page {
		padding: var(--page-padding-y) var(--page-padding-x);
	}
	.state-msg {
		margin: 0;
		color: var(--color-text-tertiary);
		font-size: 0.9rem;
	}
	.error-banner {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		padding: var(--space-sm) var(--space-md);
		background: rgba(239, 68, 68, 0.08);
		border: 1px solid rgba(239, 68, 68, 0.3);
		border-radius: var(--radius-md);
		color: var(--color-text);
	}
	.error-banner > div {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
	}
	.error-detail {
		font-size: 0.78rem;
		color: var(--color-text-tertiary);
	}
	.error-banner .material-symbols {
		color: var(--color-danger-text);
		font-size: 1.3rem;
	}
	.sheet {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}
	.sheet-actions {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-sm);
	}
	.filter-hint {
		color: var(--color-text-secondary);
		font-size: 0.85rem;
		line-height: 1.45;
		margin: 0;
	}
	.list-controls {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-sm);
		margin-bottom: var(--space-sm);
	}
	.sort {
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
		font-size: 0.9rem;
		color: var(--color-text-secondary);
	}
	.sort select {
		min-height: var(--tap-target-min);
		padding: var(--space-xs) var(--space-sm);
		border: 1.5px solid var(--color-border);
		border-radius: 9999px;
		background: var(--color-surface);
		color: var(--color-text);
	}
	.list-search {
		margin-bottom: var(--space-sm);
	}
	.results-status {
		margin-bottom: var(--space-sm);
	}
	.count {
		margin: 0;
		font-size: 0.78rem;
		color: var(--color-text-tertiary);
	}
	.cards {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		margin: 0;
		padding: 0;
		list-style: none;
	}
	.search-panel {
		width: min(100%, 30rem);
		max-height: 60vh;
		overflow-y: auto;
		padding: var(--space-sm);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		background: var(--color-surface);
		box-shadow: var(--shadow-lg);
	}
	.search-note {
		margin: var(--space-sm) var(--space-xs) 0;
		color: var(--color-text-secondary);
		font-size: 0.9rem;
	}
	.search-results {
		margin: var(--space-xs) 0 0;
		padding: 0;
		list-style: none;
	}
	.search-results button {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		width: 100%;
		min-height: var(--tap-target-min);
		padding: var(--space-xs) var(--space-sm);
		border: none;
		border-radius: var(--radius-sm);
		background: none;
		color: var(--color-text);
		text-align: start;
		cursor: pointer;
	}
	.search-results button:hover,
	.search-results button:focus-visible {
		background: var(--color-bg-secondary);
	}
	.search-results .name {
		font-weight: 600;
		overflow-wrap: anywhere;
	}
	.search-results .meta {
		color: var(--color-text-secondary);
		font-size: 0.85rem;
	}
</style>
