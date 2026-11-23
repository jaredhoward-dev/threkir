<script lang="ts">
	import { onDestroy, onMount } from 'svelte';
	import { page } from '$app/state';
	import { goto } from '$app/navigation';
	import Modal from '#lib/components/Modal.svelte';
	import ListRow from '#lib/components/ListRow.svelte';
	import AppSearchField from '#lib/components/AppSearchField.svelte';
	import EmptyState from '#lib/components/EmptyState.svelte';
	import ExploreShell from '#lib/components/ExploreShell.svelte';
	import ExploreMap from '#lib/components/ExploreMap.svelte';
	import ExploreCard from '#lib/components/ExploreCard.svelte';
	import ExploreListCard from '#lib/components/ExploreListCard.svelte';
	import ExplorePicker from '#lib/components/ExplorePicker.svelte';
	import ExploreEmptyView from '#lib/components/ExploreEmptyView.svelte';
	import ExploreMapButton from '#lib/components/ExploreMapButton.svelte';
	import RouteTrackPreview from './RouteTrackPreview.svelte';
	import { formatDistance, formatElevation, getUnit } from '#lib/format/units.svelte.ts';
	import {
		bookmarkRoute,
		fetchClippedRouteForViewer,
		fetchDiscoverableRoutesInBbox,
		searchPublicRoutes,
		unbookmarkRoute,
		type DiscoverableRoutePin,
	} from '#lib/core/data.ts';
	import type { PublicRouteSummary } from '#lib/routes/route_list_columns.ts';
	import {
		defaultSort,
		distanceBucketBounds,
		filterActive,
		filterViewport,
		inBounds,
		nearestTo,
		sortViewport,
		type DistanceBucket,
		type ExploreLine,
		type ExplorePin,
		type ExploreSort,
		type LatLng,
		type ViewBounds,
	} from '#lib/routes/explore_viewport.ts';
	import { fold } from '#lib/segments/catalogue_browse.ts';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import { showToast } from '#lib/stores/toast.svelte.ts';
	import { supabase } from '#lib/core/supabase.ts';
	import { m as t } from '#lib/i18n/store.svelte.ts';
	import { errorCopy } from '#lib/i18n/error_copy.ts';
	import { routeSurfaceLabel } from '#lib/i18n/enum_labels.svelte.ts';

	// Routes → Explore, map first (decisions § 2611): the public routes in view
	// as pins, a tapped one as a card over the map's foot, and the list of the
	// routes in view as its own view (`?view=list`). Search finds a route
	// anywhere and flies to it; the Filters sheet narrows the pins and the list.

	interface RoutePin extends ExplorePin {
		official: boolean;
		elevationM: number | null;
	}

	const listOpen = $derived(page.url.searchParams.get('view') === 'list');
	const mapHref = '/routes?tab=explore';
	const listHref = '/routes?tab=explore&view=list';

	let mapRef: ReturnType<typeof ExploreMap> | undefined = $state();

	let raw = $state<DiscoverableRoutePin[]>([]);
	let loaded = $state(false);
	let loadFailed = $state(false);
	let fetching = $state(false);
	let center = $state<LatLng | null>(null);
	let bounds = $state<ViewBounds | null>(null);
	let origin = $state<LatLng | null>(null);
	/// Every route seen this visit, for the empty view's nearest one.
	const seen = new Map<string, RoutePin>();

	let distance = $state<DistanceBucket>('any');
	let surface = $state<string | null>(null);
	let featuredOnly = $state(false);
	let filtersOpen = $state(false);

	let sortChoice = $state<ExploreSort | null>(null);
	let listQuery = $state('');

	let selectedId = $state<string | null>(null);
	/// A search result off the current map, until the map moves to it.
	let selectedExtra = $state<RoutePin | null>(null);
	let selectedLine = $state<[number, number][]>([]);
	let pickIds = $state<string[] | null>(null);

	let searchOpen = $state(false);
	let searchQuery = $state('');
	let searchResults = $state<PublicRouteSummary[]>([]);
	let searching = $state(false);
	let searchFailed = $state(false);
	let searchTimer: ReturnType<typeof setTimeout> | null = null;

	let savedIds = $state<Set<string>>(new Set());
	let bookmarkBusy = $state(new Set<string>());
	let locating = $state(false);

	/// Set when this page opened the list from the map, so leaving the list
	/// goes back in history rather than stacking another map entry.
	let listFromMap = false;

	function toPin(p: DiscoverableRoutePin): RoutePin {
		return {
			id: p.id,
			name: p.name,
			lat: p.lat,
			lng: p.lng,
			distanceM: p.distance_m,
			surface: p.surface,
			featured: p.is_featured,
			runCount: p.run_count,
			official: p.is_official,
			elevationM: p.elevation_m,
		};
	}

	const filter = $derived({ distance, unit: getUnit(), surface, featuredOnly });
	const filtering = $derived(filterActive({ distance, surface, featuredOnly }));
	const pins = $derived(filterViewport(raw.map(toPin), filter));
	const sort = $derived(sortChoice ?? defaultSort(origin));
	const listed = $derived.by(() => {
		const q = fold(listQuery.trim());
		const narrowed = q ? pins.filter((p) => fold(p.name).includes(q)) : pins;
		return sortViewport(narrowed, sort, origin);
	});
	const selected = $derived(pins.find((p) => p.id === selectedId) ?? (selectedExtra?.id === selectedId ? selectedExtra : null));
	const lines = $derived<ExploreLine[]>(selectedId && selectedLine.length > 1 ? [{ id: selectedId, coords: selectedLine }] : []);
	const pickItems = $derived(
		(pickIds ?? [])
			.map((id) => pins.find((p) => p.id === id))
			.filter((p): p is RoutePin => !!p)
			.map((p) => ({ id: p.id, name: p.name, stats: stats(p) })),
	);
	const emptyView = $derived(loaded && !loadFailed && !fetching && pins.length === 0 && !selected);
	const nearest = $derived.by(() => {
		if (!emptyView || !center) return null;
		const candidates = filterViewport([...seen.values()], filter).filter((p) => !bounds || !inBounds(p.lat, p.lng, bounds));
		return nearestTo(candidates, center);
	});

	function stats(p: RoutePin): string {
		return [
			formatDistance(p.distanceM),
			p.elevationM ? `${formatElevation(p.elevationM)} ↑` : null,
			p.surface ? routeSurfaceLabel(p.surface) : null,
		]
			.filter(Boolean)
			.join(' · ');
	}

	let moveTimer: ReturnType<typeof setTimeout> | null = null;
	let generation = 0;

	function onMove(b: ViewBounds, c: LatLng) {
		bounds = b;
		center = c;
		if (moveTimer) clearTimeout(moveTimer);
		moveTimer = setTimeout(() => void refresh(), 300);
	}

	async function refresh() {
		moveTimer = null;
		const b = bounds;
		if (!b) return;
		const gen = ++generation;
		fetching = true;
		try {
			const rows = await fetchDiscoverableRoutesInBbox({ minLng: b.west, minLat: b.south, maxLng: b.east, maxLat: b.north });
			if (gen !== generation) return;
			raw = rows;
			for (const r of rows) seen.set(r.id, toPin(r));
			loadFailed = false;
		} catch (e) {
			if (gen !== generation) return;
			console.warn('explore map routes read failed', e);
			loadFailed = true;
		} finally {
			if (gen === generation) {
				fetching = false;
				loaded = true;
			}
		}
	}

	async function select(id: string, opts: { frame?: boolean } = {}) {
		selectedId = id;
		pickIds = null;
		selectedLine = [];
		try {
			const pts = await fetchClippedRouteForViewer(id);
			if (selectedId !== id) return;
			selectedLine = pts.map((p) => [p.lng, p.lat]);
			if (opts.frame) mapRef?.fitLine(selectedLine);
		} catch (e) {
			console.warn('explore route line read failed', e);
		}
	}

	function onPick(ids: string[]) {
		if (ids.length === 1) void select(ids[0]);
		else if (ids.length > 1) pickIds = ids;
	}

	function closeCard() {
		selectedId = null;
		selectedExtra = null;
		selectedLine = [];
	}

	function backToMap() {
		if (listFromMap) {
			listFromMap = false;
			history.back();
		} else {
			void goto(mapHref, { replace: true, reset: false });
		}
	}

	function openFromList(id: string) {
		backToMap();
		void select(id, { frame: true });
	}

	function locate() {
		if (typeof navigator === 'undefined' || !navigator.geolocation) {
			showToast(t('routeExplorer.locationError', { error: '' }), 'error');
			return;
		}
		locating = true;
		navigator.geolocation.getCurrentPosition(
			(pos) => {
				locating = false;
				origin = { lat: pos.coords.latitude, lng: pos.coords.longitude };
				mapRef?.flyTo(origin, 12);
			},
			(err) => {
				locating = false;
				showToast(
					err.code === err.PERMISSION_DENIED
						? t('routeExplorer.locationDenied')
						: t('routeExplorer.locationError', { error: errorCopy(err, t, 'routeExplorer.locationError') }),
					'error',
				);
			},
			{ enableHighAccuracy: false, timeout: 10000, maximumAge: 60000 },
		);
	}

	/// Where the reader is, read only if they already allowed it, so the page
	/// never opens on a permission prompt.
	async function quietLocate() {
		try {
			const state = await navigator.permissions?.query({ name: 'geolocation' });
			if (state?.state !== 'granted') return;
			navigator.geolocation.getCurrentPosition(
				(pos) => {
					origin = { lat: pos.coords.latitude, lng: pos.coords.longitude };
					if (!selectedId) mapRef?.flyTo(origin, 12);
				},
				() => {},
				{ enableHighAccuracy: false, timeout: 10000, maximumAge: 300000 },
			);
		} catch {
			// No Permissions API: stay on the world until Near me is pressed.
		}
	}

	function runSearch() {
		if (searchTimer) clearTimeout(searchTimer);
		const q = searchQuery.trim();
		if (!q) {
			searchResults = [];
			searchFailed = false;
			return;
		}
		searchTimer = setTimeout(async () => {
			searching = true;
			const { min, max } = distanceBucketBounds(distance, getUnit());
			try {
				const res = await searchPublicRoutes({
					query: q,
					minDistanceM: min ?? undefined,
					maxDistanceM: max ?? undefined,
					surface: surface ?? undefined,
					featuredOnly,
					sort: 'popular',
					limit: 20,
				});
				if (searchQuery.trim() !== q) return;
				searchResults = res.rows;
				searchFailed = false;
			} catch (e) {
				searchFailed = true;
				console.warn('explore search failed', e);
			} finally {
				searching = false;
			}
		}, 300);
	}

	async function openSearchResult(r: PublicRouteSummary) {
		searchOpen = false;
		selectedExtra = {
			id: r.id,
			name: r.name ?? '',
			lat: 0,
			lng: 0,
			distanceM: r.distance_m ?? 0,
			surface: r.surface ?? '',
			featured: !!r.is_featured,
			runCount: r.run_count ?? 0,
			official: !!r.is_official,
			elevationM: r.elevation_m ?? null,
		};
		await select(r.id, { frame: true });
	}

	function clearFilters() {
		distance = 'any';
		surface = null;
		featuredOnly = false;
	}

	async function toggleBookmark(route: { id: string; name: string }) {
		if (!auth.loggedIn || bookmarkBusy.has(route.id)) return;
		bookmarkBusy = new Set([...bookmarkBusy, route.id]);
		const isSaved = savedIds.has(route.id);
		try {
			if (isSaved) {
				await unbookmarkRoute(route.id);
				const next = new Set(savedIds);
				next.delete(route.id);
				savedIds = next;
				showToast(t('routeExplorer.toastRemoved', { name: route.name }));
			} else {
				await bookmarkRoute(route.id);
				savedIds = new Set([...savedIds, route.id]);
				showToast(t('routeExplorer.toastSaved', { name: route.name }), 'success');
			}
		} catch (e) {
			showToast(
				t('routeExplorer.toastBookmarkError', { error: errorCopy(e, t, 'routeExplorer.toastBookmarkError') }),
				'error',
			);
		} finally {
			const next = new Set(bookmarkBusy);
			next.delete(route.id);
			bookmarkBusy = next;
		}
	}

	async function loadSavedIds() {
		if (!auth.loggedIn) return;
		const { data } = await supabase.from('saved_routes').select('route_id').limit(1000);
		savedIds = new Set((data ?? []).map((r) => r.route_id as string));
	}

	function onKey(e: KeyboardEvent) {
		if (e.key !== 'Escape') return;
		if (pickIds) pickIds = null;
		else if (searchOpen) searchOpen = false;
		else if (selectedId) closeCard();
	}

	onMount(() => {
		loadSavedIds();
		void quietLocate();
		if (import.meta.env.DEV) {
			(window as unknown as { __explorePinsSettled?: () => boolean }).__explorePinsSettled = () =>
				loaded && !fetching && moveTimer === null;
		}
	});

	onDestroy(() => {
		if (moveTimer) clearTimeout(moveTimer);
		if (searchTimer) clearTimeout(searchTimer);
		if (import.meta.env.DEV && typeof window !== 'undefined') {
			(window as unknown as { __explorePinsSettled?: unknown }).__explorePinsSettled = undefined;
		}
	});

	const distanceOptions = $derived<[DistanceBucket, string][]>(
		getUnit() === 'mi'
			? [
					['any', t('routeExplorer.distanceAny')],
					['short', t('routeExplorer.distanceUnder3Mi')],
					['medium', t('routeExplorer.distance3to6Mi')],
					['long', t('routeExplorer.distance6to13Mi')],
					['ultra', t('routeExplorer.distance13MiPlus')],
				]
			: [
					['any', t('routeExplorer.distanceAny')],
					['short', t('routeExplorer.distanceUnder5Km')],
					['medium', t('routeExplorer.distance5to10Km')],
					['long', t('routeExplorer.distance10to21Km')],
					['ultra', t('routeExplorer.distance21KmPlus')],
				],
	);
	const filterCount = $derived((distance !== 'any' ? 1 : 0) + (surface !== null ? 1 : 0) + (featuredOnly ? 1 : 0));
</script>

<svelte:window onkeydown={onKey} />

<Modal open={filtersOpen} onclose={() => (filtersOpen = false)} title={t('filterBar.filters')} data-testid="explore-filters">
	<div class="editor-form sheet">
		<label class="field">
			<span>{t('routeExplorer.filterDistance')}</span>
			<select bind:value={distance} data-testid="explore-filter-distance">
				{#each distanceOptions as [key, label] (key)}
					<option value={key}>{label}</option>
				{/each}
			</select>
		</label>
		<label class="field">
			<span>{t('routeExplorer.filterSurface')}</span>
			<select bind:value={surface} data-testid="explore-filter-surface">
				<option value={null}>{t('routeExplorer.surfaceAny')}</option>
				<option value="road">{routeSurfaceLabel('road')}</option>
				<option value="trail">{routeSurfaceLabel('trail')}</option>
				<option value="mixed">{routeSurfaceLabel('mixed')}</option>
			</select>
		</label>
		<ListRow kind="toggle" title={t('routeExplorer.featuredOnly')} bind:checked={featuredOnly} testid="explore-filter-featured" />
		<div class="sheet-actions">
			{#if filtering}
				<button type="button" class="btn btn-outline" onclick={clearFilters}>{t('routeExplorer.clearFilters')}</button>
			{/if}
			<button type="button" class="btn btn-primary" onclick={() => (filtersOpen = false)}>{t('filterBar.done')}</button>
		</div>
	</div>
</Modal>

<ExploreShell
	view="routes"
	{listOpen}
	{listHref}
	listLabel={t('exploreMap.listRoutes', { count: pins.length })}
	listTitle={t('exploreMap.listRoutesTitle')}
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
			label={t('exploreMap.mapLabelRoutes')}
			onmove={onMove}
			onpick={onPick}
			testid="explore-routes-map"
		/>
	{/snippet}

	{#snippet toolbar()}
		<ExploreMapButton
			round
			icon="search"
			label={t('routeExplorer.searchAriaLabel')}
			onclick={() => (searchOpen = !searchOpen)}
			testid="explore-search-open"
		/>
		<ExploreMapButton
			round
			icon="tune"
			label={filterCount > 0 ? t('filterBar.filtersCount', { count: filterCount }) : t('filterBar.filters')}
			count={filterCount}
			onclick={() => (filtersOpen = true)}
			testid="explore-filters-open"
		/>
	{/snippet}

	{#snippet mapButtons()}
		<ExploreMapButton href="/routes/heatmap" icon="local_fire_department" label={t('exploreMap.popularRoutes')} testid="explore-popular" />
		<ExploreMapButton href="/runs/heatmap" icon="person_pin_circle" label={t('exploreMap.whereYouRan')} testid="explore-where-run" />
		<ExploreMapButton icon="near_me" label={t('discover.nearMe')} pressed={origin !== null && !locating} onclick={locate} testid="explore-near-me" />
	{/snippet}

	{#snippet overlay()}
		{#if searchOpen}
			<div class="search-panel" data-testid="explore-search-panel">
				<form role="search" onsubmit={(e) => { e.preventDefault(); runSearch(); }}>
					<AppSearchField
						bind:value={searchQuery}
						label={t('routeExplorer.searchAriaLabel')}
						placeholder={t('routeExplorer.searchPlaceholder')}
						clearLabel={t('routeExplorer.clearSearch')}
						oninput={runSearch}
						testid="explore-search"
					/>
				</form>
				{#if searching}
					<p class="search-note" role="status">{t('routeExplorer.searchingStatus')}</p>
				{:else if searchFailed}
					<p class="search-note" role="alert">{t('routeExplorer.searchErrorTitle')}</p>
				{:else if searchQuery.trim() && searchResults.length === 0}
					<p class="search-note" role="status">{t('routeExplorer.emptyNoMatch')}</p>
				{/if}
				{#if searchResults.length > 0}
					<ul class="search-results">
						{#each searchResults as r (r.id)}
							<li>
								<button type="button" onclick={() => void openSearchResult(r)} data-testid="explore-search-result">
									<span class="name">{r.name}</span>
									<span class="meta">{formatDistance(r.distance_m ?? 0)}</span>
								</button>
							</li>
						{/each}
					</ul>
				{/if}
			</div>
		{:else if pickIds}
			<ExplorePicker title={t('exploreMap.whichRoute')} items={pickItems} onpick={(id) => void select(id)} onclose={() => (pickIds = null)} />
		{:else if loadFailed}
			<div class="map-note" role="alert" data-testid="explore-load-failed">
				<span>{t('exploreMap.loadFailed')}</span>
				<button type="button" class="btn btn-outline btn-sm" onclick={() => void refresh()}>{t('routeExplorer.searchErrorRetry')}</button>
			</div>
		{:else if emptyView}
			<ExploreEmptyView
				title={t('exploreMap.emptyRoutes')}
				onzoomout={() => mapRef?.zoomOut()}
				onclearfilters={filtering ? clearFilters : undefined}
				nearest={nearest ? { name: nearest.name, onclick: () => { const n = nearest; if (n) { mapRef?.flyTo(n, 13); void select(n.id); } } } : null}
			/>
		{/if}
	{/snippet}

	{#snippet card()}
		{#if selected}
			<ExploreCard name={selected.name} official={selected.official} stats={stats(selected)} onclose={closeCard} testid="explore-route-card">
				{#snippet actions()}
					<a class="btn btn-primary" href="/routes/{selected.id}?from=explore" data-testid="explore-card-see-route">
						{t('parks.seeRoute')}
					</a>
					{#if auth.loggedIn}
						<button
							type="button"
							class="btn btn-outline save"
							aria-pressed={savedIds.has(selected.id)}
							disabled={bookmarkBusy.has(selected.id)}
							onclick={() => selected && void toggleBookmark(selected)}
							data-testid="explore-card-save"
						>
							<span class="material-symbols" aria-hidden="true">{savedIds.has(selected.id) ? 'bookmark' : 'bookmark_add'}</span>
							{savedIds.has(selected.id) ? t('routeExplorer.removeFromLibrary') : t('routeExplorer.saveToLibrary')}
						</button>
					{/if}
				{/snippet}
			</ExploreCard>
		{/if}
	{/snippet}

	{#snippet list()}
		<div class="list-controls">
			<label class="sort">
				<span>{t('exploreMap.sortLabel')}</span>
				<select
					value={sort}
					onchange={(e) => (sortChoice = (e.currentTarget as HTMLSelectElement).value as ExploreSort)}
					data-testid="explore-sort"
				>
					{#if origin}<option value="nearest">{t('exploreMap.sortNearest')}</option>{/if}
					<option value="most_run">{t('routeExplorer.sortMostRun')}</option>
					<option value="name">{t('exploreMap.sortName')}</option>
				</select>
			</label>
			<button type="button" class="btn btn-outline btn-sm list-filters" onclick={() => (filtersOpen = true)}>
				<span class="material-symbols" aria-hidden="true">tune</span>
				{filterCount > 0 ? t('filterBar.filtersCount', { count: filterCount }) : t('filterBar.filters')}
			</button>
		</div>
		<div class="list-search">
			<AppSearchField
				bind:value={listQuery}
				label={t('exploreMap.listSearchLabel')}
				placeholder={t('exploreMap.listSearchLabel')}
				clearLabel={t('routeExplorer.clearSearch')}
				testid="explore-list-search"
			/>
		</div>
		{#if listed.length === 0}
			<EmptyState
				icon="explore"
				title={pins.length === 0 ? t('exploreMap.emptyRoutes') : t('routeExplorer.emptyNoMatch')}
				text={pins.length === 0 ? t('exploreMap.emptyRoutesHint') : undefined}
			/>
		{:else}
			<ul class="cards">
				{#each listed as p (p.id)}
					<li>
						<ExploreListCard
							name={p.name}
							official={p.official}
							stats={stats(p)}
							onclick={() => openFromList(p.id)}
							testid="explore-list-card"
						>
							{#snippet thumbnail()}
								<RouteTrackPreview routeId={p.id} waypoints={[]} ownerUserId="" />
							{/snippet}
						</ExploreListCard>
					</li>
				{/each}
			</ul>
		{/if}
	{/snippet}
</ExploreShell>

<style>
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
	.map-note {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-sm) var(--space-md);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		background: var(--color-surface);
		box-shadow: var(--shadow-md);
	}
	.save .material-symbols {
		font-size: 1.1rem;
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
		margin-bottom: var(--space-md);
	}
	.cards {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		margin: 0;
		padding: 0;
		list-style: none;
	}
	@media (min-width: 40.0625rem) {
		.list-filters {
			display: none;
		}
	}
</style>
