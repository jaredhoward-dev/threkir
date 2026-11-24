<script lang="ts">
	import SectionHeader from '#lib/components/SectionHeader.svelte';
	import PageHeader from '#lib/components/PageHeader.svelte';
	import InfoTip from '#lib/components/InfoTip.svelte';
	import { onMount, tick } from 'svelte';
	import { goto } from '$app/navigation';
	import { page } from '$app/state';
	import { m } from '#lib/i18n/store.svelte.ts';
	import EmptyState from '#lib/components/EmptyState.svelte';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import { fetchAllParkCourses, fetchParks, type Park, type ParkCourseWithPark } from '#lib/core/data.ts';
	import { groupParksByRegion, regionName, regionSlug } from '#lib/parks/park_courses.ts';
	import { countInView, parkMarkerPoint, type MapBounds } from '#lib/parks/park_map.ts';
	import ParkCard from '#lib/components/parks/ParkCard.svelte';
	import ParksMap, { type ParkPin } from '#lib/components/parks/ParksMap.svelte';
	import AppSearchField from '#lib/components/AppSearchField.svelte';
	import { parkSearchMatches, parkSearchTerms } from '#lib/parks/any_time_courses.ts';
	import { hasAcceptedConsent } from '#lib/settings/consent.svelte.ts';

	// Map first (decisions § 2612): every park on a map, with the grouped list
	// one tap away under `?view=list`, so the browser's back returns to the
	// map. From 64rem the list sits beside the map and both show at once. The
	// list is in the page in either view, so every park link is in the DOM.

	let parks = $state<Park[]>([]);
	let loading = $state(true);
	let loadFailed = $state(false);
	// The courses are an auxiliary read: when it fails the parks still list,
	// without their course count, distances and thumbnail.
	let courses = $state<ParkCourseWithPark[]>([]);

	// The search once typing pauses. Every park and course is already loaded,
	// so it is matched on the list. A park is found by its own name and place,
	// or by any of its courses' names, so a course name leads to its park.
	// Opens on `?q=`, which Races & courses' "See all" carries.
	let query = $state(page.url.searchParams.get('q') ?? '');
	let settledQuery = $state(page.url.searchParams.get('q') ?? '');
	let queryTimer: ReturnType<typeof setTimeout> | undefined;
	$effect(() => {
		const next = query;
		clearTimeout(queryTimer);
		queryTimer = setTimeout(() => (settledQuery = next), 250);
		return () => clearTimeout(queryTimer);
	});
	const terms = $derived(parkSearchTerms(settledQuery));

	function clearSearch() {
		clearTimeout(queryTimer);
		query = '';
		settledQuery = '';
	}

	const byPark = $derived.by(() => {
		const out = new Map<string, ParkCourseWithPark[]>();
		for (const c of courses) {
			const list = out.get(c.park_id);
			if (list) list.push(c);
			else out.set(c.park_id, [c]);
		}
		return out;
	});

	const shownParks = $derived(
		terms.length === 0
			? parks
			: parks.filter(
					(p) =>
						parkSearchMatches(terms, { parkName: p.name, regionCode: p.region_code }) ||
						(byPark.get(p.id) ?? []).some((c) =>
							parkSearchMatches(terms, {
								courseName: c.segment.name,
								parkName: p.name,
								regionCode: p.region_code,
							}),
						),
				),
	);

	const groups = $derived(groupParksByRegion(shownParks));

	const pins = $derived.by<ParkPin[]>(() => {
		const out: ParkPin[] = [];
		for (const p of shownParks) {
			const own = byPark.get(p.id) ?? [];
			const point = parkMarkerPoint(
				{ lat: p.centroid_lat, lng: p.centroid_lng },
				own.map((c) => c.segment.waypoints.map((w) => ({ lat: Number(w.lat), lng: Number(w.lng) }))),
			);
			if (!point) continue;
			out.push({
				id: p.id,
				href: `/parks/${regionSlug(p.region_code)}/${p.slug}`,
				name: p.name,
				count: own.length,
				point,
			});
		}
		return out;
	});

	// The map's last settled view; null until a drawn map reports one, when
	// every park shown counts as in view.
	let view = $state<MapBounds | null>(null);
	let mapShown = $state(hasAcceptedConsent());
	const inView = $derived(
		mapShown && view
			? countInView(
					pins.map((p) => p.point),
					view,
				)
			: shownParks.length,
	);

	const listOpen = $derived(page.url.searchParams.get('view') === 'list');
	let listHeading = $state<HTMLElement | null>(null);

	function withView(list: boolean): string {
		const params = new URLSearchParams(page.url.search);
		if (list) params.set('view', 'list');
		else params.delete('view');
		const qs = params.toString();
		return `${page.url.pathname}${qs ? `?${qs}` : ''}`;
	}

	async function openList() {
		await goto(withView(true), { persistState: true, state: { ...page.state, fromMap: true } });
		await tick();
		listHeading?.focus({ preventScroll: true });
	}

	async function showMap() {
		if (page.state.fromMap) history.back();
		else await goto(withView(false), { replace: true, persistState: true, state: { ...page.state, fromMap: false } });
	}

	let mapRef = $state<ReturnType<typeof ParksMap> | null>(null);
	let geoError = $state('');

	function nearMe() {
		geoError = '';
		if (typeof navigator === 'undefined' || !navigator.geolocation) {
			geoError = m('discover.geoNeedsHttps');
			return;
		}
		navigator.geolocation.getCurrentPosition(
			(pos) => mapRef?.showPlace({ lat: pos.coords.latitude, lng: pos.coords.longitude }),
			() => (geoError = m('discover.geoFailed')),
			{ enableHighAccuracy: false, timeout: 15000, maximumAge: 60000 },
		);
	}

	async function loadCourses() {
		try {
			courses = await fetchAllParkCourses();
		} catch (e) {
			console.error('park courses read failed', e);
		}
	}

	async function load() {
		loading = true;
		loadFailed = false;
		const coursesRead = loadCourses();
		try {
			parks = await fetchParks();
		} catch (e) {
			console.error('fetchParks failed', e);
			loadFailed = true;
		} finally {
			loading = false;
		}
		await coursesRead;
	}

	onMount(async () => {
		await auth.ready();
		await load();
	});
</script>

<svelte:head><title>{m('parks.title')}</title></svelte:head>

<div class="page">
	<a href="/races" class="back-link" data-testid="parks-back-to-races">
		<span class="material-symbols" aria-hidden="true">arrow_back</span>
		{m('races.pageTitle')}
	</a>
	<PageHeader title={m('parks.title')} flush>
		{#snippet help()}
			<InfoTip
				label={m('parks.howItWorks')}
				title={m('parks.howItWorks')}
				body={m('parks.intro')}
				guide="park-courses"
				testId="parks-how-it-works"
			/>
		{/snippet}
	</PageHeader>

	{#if loading}
		<p class="state-msg">{m('parks.loading')}</p>
	{:else if loadFailed}
		<EmptyState icon="error" tone="danger" title={m('parks.loadFailed')} role="alert" data-testid="parks-load-error">
			{#snippet actions()}
				<button type="button" class="btn btn-outline" onclick={load}>{m('parks.retry')}</button>
			{/snippet}
		</EmptyState>
	{:else if parks.length === 0}
		<EmptyState icon="park" title={m('parks.empty')} text={m('parks.intro')} data-testid="parks-empty">
			{#snippet actions()}
				<a class="btn btn-outline" href="/segments">
					<span class="material-symbols" aria-hidden="true">terrain</span>
					{m('runSurface.tabSegments')}
				</a>
			{/snippet}
		</EmptyState>
	{:else}
		<div class="parks-body" class:list-open={listOpen}>
			<div class="parks-search">
				<AppSearchField bind:value={query} label={m('parks.searchPlaceholder')} testid="parks-search" />
				{#if geoError}<p class="geo-error" role="status" data-testid="parks-geo-error">{geoError}</p>{/if}
			</div>

			<section class="map-pane" aria-label={m('parks.mapLabel')}>
				<ParksMap
					bind:this={mapRef}
					parks={pins}
					label={m('parks.mapLabel')}
					onview={(b) => (view = b)}
					bind:consented={mapShown}
					testid="parks-map"
				/>
				{#if mapShown}
					<button type="button" class="btn btn-secondary btn-sm near-me" onclick={nearMe} data-testid="parks-near-me">
						<span class="material-symbols" aria-hidden="true">near_me</span>
						{m('races.nearMe')}
					</button>
				{/if}
				<button type="button" class="btn btn-primary list-button" onclick={() => void openList()} data-testid="parks-list-button">
					<span class="material-symbols" aria-hidden="true">list</span>
					{m('parks.listButton', { n: inView })}
				</button>
			</section>

			<section class="list-pane" aria-labelledby="parks-list-title" data-testid="parks-list">
				<div class="list-head">
					<h2 id="parks-list-title" class="visually-hidden" tabindex="-1" bind:this={listHeading}>{m('parks.title')}</h2>
					<button type="button" class="btn btn-outline btn-sm map-button" onclick={() => void showMap()} data-testid="parks-map-button">
						<span class="material-symbols" aria-hidden="true">map</span>
						{m('parks.showMap')}
					</button>
				</div>
				{#if groups.length === 0}
					<EmptyState icon="search_off" title={m('parks.noMatch', { query: settledQuery.trim() })} data-testid="parks-no-match">
						{#snippet actions()}
							<button type="button" class="btn btn-outline" onclick={clearSearch} data-testid="parks-clear-search">
								{m('filterBar.clearSearch')}
							</button>
						{/snippet}
					</EmptyState>
				{/if}
				{#each groups as group (group.regionCode)}
					<section class="region" data-testid="parks-region" aria-labelledby="region-{group.regionCode}">
						<SectionHeader label={regionName(group.regionCode)} id="region-{group.regionCode}" class="parks-region-head" />
						<ul class="park-grid">
							{#each group.parks as park (park.id)}
								<li><ParkCard {park} courses={byPark.get(park.id) ?? []} /></li>
							{/each}
						</ul>
					</section>
				{/each}
			</section>
		</div>
	{/if}
</div>

<style>
	.page {
		padding: var(--page-padding-y) var(--page-padding-x);
	}
	.back-link {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
		min-height: var(--tap-target-min);
		color: var(--color-text-secondary);
		font-size: 0.85rem;
		text-decoration: none;
	}
	.state-msg {
		color: var(--color-text-tertiary);
	}
	.parks-body {
		position: relative;
		display: grid;
		grid-template-columns: minmax(0, 1fr);
		grid-template-areas: 'map';
		margin-top: var(--space-md);
	}
	.parks-search {
		grid-area: map;
		align-self: start;
		z-index: 2;
		margin: var(--space-sm);
		max-width: 32rem;
	}
	.geo-error {
		margin: var(--space-xs) 0 0;
		padding: var(--space-xs) var(--space-sm);
		border-radius: var(--radius-sm);
		background: var(--color-surface);
		font-size: 0.85rem;
	}
	.map-pane {
		grid-area: map;
		position: relative;
		height: max(22rem, calc(100dvh - 14rem));
		border-radius: var(--radius-md);
		overflow: hidden;
		border: 1px solid var(--color-border);
	}
	.near-me {
		position: absolute;
		top: calc(var(--space-sm) * 2 + var(--tap-target-min) + var(--space-xs));
		inset-inline-end: var(--space-sm);
		z-index: 1;
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
		min-height: var(--tap-target-min);
	}
	.list-button {
		position: absolute;
		bottom: var(--space-md);
		inset-inline: var(--space-md);
		width: fit-content;
		margin-inline: auto;
		/* Over MapLibre's control corners (z-index 2): a narrow map opens its
		   attribution expanded across the bottom edge, which took the tap. The
		   Explore map's list pill sits at the same height (ExploreShell). */
		z-index: 5;
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
		min-height: var(--tap-target-min);
		border-radius: var(--radius-pill);
		box-shadow: var(--shadow-md);
	}
	.list-pane {
		display: none;
	}
	.list-head {
		display: flex;
		justify-content: flex-start;
	}
	.map-button {
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
		min-height: var(--tap-target-min);
	}
	/* The list view on a phone: the map steps aside and the search sits above
	   the list rather than over the map. */
	.parks-body.list-open {
		grid-template-areas:
			'search'
			'list';
	}
	.parks-body.list-open .parks-search {
		grid-area: search;
		margin: 0 0 var(--space-sm);
	}
	.parks-body.list-open .map-pane {
		display: none;
	}
	.parks-body.list-open .list-pane {
		display: block;
		grid-area: list;
	}
	@media (min-width: 64rem) {
		.parks-body,
		.parks-body.list-open {
			grid-template-columns: minmax(0, 3fr) minmax(0, 2fr);
			grid-template-areas:
				'map search'
				'map list';
			grid-template-rows: auto 1fr;
			column-gap: var(--space-lg);
			align-items: start;
		}
		.parks-search,
		.parks-body.list-open .parks-search {
			grid-area: search;
			margin: 0 0 var(--space-sm);
		}
		.map-pane,
		.parks-body.list-open .map-pane {
			display: block;
			grid-area: map;
			position: sticky;
			top: var(--space-md);
			height: min(44rem, calc(100dvh - 8rem));
		}
		.list-pane,
		.parks-body.list-open .list-pane {
			display: block;
			grid-area: list;
		}
		.list-button,
		.list-head {
			display: none;
		}
	}
	:global(.parks-region-head) {
		margin-top: var(--space-lg);
	}
	.park-grid {
		list-style: none;
		margin: 0;
		padding: 0;
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(min(20rem, 100%), 1fr));
		gap: var(--space-md);
	}
</style>
