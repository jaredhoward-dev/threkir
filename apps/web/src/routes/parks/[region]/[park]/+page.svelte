<script lang="ts">
	import SectionHeader from '#lib/components/SectionHeader.svelte';
	import ListCard from '#lib/components/ListCard.svelte';
	import { onMount, tick } from 'svelte';
	import { goto } from '$app/navigation';
	import { page } from '$app/state';
	import { m } from '#lib/i18n/store.svelte.ts';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import { formatDistance, formatElevation } from '#lib/format/units.svelte.ts';
	import { formatDuration } from '#lib/format/time.ts';
	import {
		fetchPark,
		fetchParkCourseMonthRunners,
		fetchParkCourseRecords,
		fetchParkCourses,
		type Park,
		type ParkCourse,
		type ParkCourseRecord,
	} from '#lib/core/data.ts';
	import { courseEnds, courseOffersWayfinding, regionCodeFromSlug, regionName } from '#lib/parks/park_courses.ts';
	import { parkCourseLineColour } from '#lib/parks/park_course_colours.ts';
	import { routeSurfaceLabel } from '#lib/i18n/enum_labels.svelte.ts';
	import { PUBLIC_MAPTILER_KEY as PUBLIC_MAPTILER_KEY_ENV } from '$app/env/public';
	import { basemapIsDarkFromEnv } from '#lib/routes/map-style.svelte.ts';
	import { courseSearch, selectedCourseSlug, startSentence } from '#lib/parks/course_preview.ts';
	import { hasAcceptedConsent } from '#lib/settings/consent.svelte.ts';
	import { parseRouteGuide } from '#lib/parks/route_guide.ts';
	import { referrerBack } from '#lib/util/referrer_back.svelte.ts';
	import { BACK_PLACE_KEY } from '#lib/util/back_target.ts';
	import {
		DIFFICULTY_LABEL,
		SHAPE_LABEL,
		STATUS_LABEL,
		labelKey,
		parkTypeKey,
	} from '#lib/parks/park_labels.ts';
	import {
		courseDisplayNames,
		courseLapsChip,
		courseShapeShown,
		sortParkCourses,
	} from '#lib/parks/park_course_distance.ts';
	import { fmtCourseDistance } from '#lib/parks/course_distance_format.ts';
	import EmptyState from '#lib/components/EmptyState.svelte';
	import ParkCoursesMap from '#lib/components/parks/ParkCoursesMap.svelte';
	import ParkMapLegend, { type ParkMapLegendItem } from '#lib/components/parks/ParkMapLegend.svelte';
	import type { TrackPoint } from '#lib/types.ts';

	// Map first (decisions § 2612): the park's name once, a large map with
	// every course in its own colour, then roomy course cards whose strip
	// repeats that colour. A card or a line previews its course: the line is
	// drawn over the others faded, its start says "Start here", and a card
	// floats at the bottom with See the route and Board. The description, the
	// website and the notices fold into "About this park" at the end.

	let { data } = $props();

	// With no in-app history a park sits under Races & courses, the place the
	// sidebar names; the parks index is one step further from the nav.
	const back = referrerBack({ href: '/races?show=courses', place: 'races' });

	let park = $state<Park | null>(null);
	let courses = $state<ParkCourse[]>([]);
	let loading = $state(true);
	let loadFailed = $state(false);
	// The season's records are an auxiliary read on their own: when it fails
	// the courses still list, without records. Signed out, there is none.
	let records = $state<Map<string, ParkCourseRecord>>(new Map());
	let recordsLoaded = $state(false);
	let recordsFailed = $state(false);
	// How many ran each course this month where the park is, an auxiliary
	// read of its own like the records. A course nobody ran this month has
	// no entry and no line.
	let monthRunners = $state<Map<string, number>>(new Map());
	let monthRunnersFailed = $state(false);
	let highlightId = $state<string | null>(null);

	const sorted = $derived(
		sortParkCourses(courses, (c) => ({
			distanceM: Number(c.segment.distance_m),
			name: c.segment.name,
			slug: c.slug,
			status: c.status,
		})),
	);

	function pointsOf(course: ParkCourse): TrackPoint[] {
		return course.segment.waypoints.map((w) => ({ lat: Number(w.lat), lng: Number(w.lng), ele: w.ele }));
	}

	const prefersDark = typeof window !== 'undefined' && window.matchMedia('(prefers-color-scheme: dark)').matches;
	const darkBasemap = basemapIsDarkFromEnv(PUBLIC_MAPTILER_KEY_ENV ?? '', prefersDark);
	const colourOf = $derived(new Map(sorted.map((c, i) => [c.id, parkCourseLineColour(i, darkBasemap)])));
	const mapCourses = $derived(
		sorted.map((c) => ({ id: c.id, points: pointsOf(c), colour: colourOf.get(c.id) ?? parkCourseLineColour(0, darkBasemap) })),
	);
	// A stored `road` surface is a paved course (decisions § 2582).
	const surfaceLabel = (surface: string) => (surface === 'road' ? m('parks.surfacePaved') : routeSurfaceLabel(surface));
	/** The facts after a card's distance: its climb and its surface. */
	function statsAfterDistance(c: ParkCourse): string[] {
		const gain = Number(c.segment.elevation_m);
		return [
			Number.isFinite(gain) && gain > 0 ? m('parks.courseClimb', { elevation: formatElevation(gain) }) : null,
			c.segment.surface ? surfaceLabel(c.segment.surface) : null,
		].filter((x): x is string => !!x);
	}
	function recordLine(courseId: string): string | null {
		const record = records.get(courseId);
		if (!record || !auth.loggedIn || recordsFailed) return null;
		return record.displayName
			? m('races.anyTimeFastestBy', { year: record.season, time: formatDuration(record.timeSeconds), name: record.displayName })
			: m('races.anyTimeFastest', { year: record.season, time: formatDuration(record.timeSeconds) });
	}
	// Each card's name, without the distance and laps it states where the
	// shorter name stays unique in the park.
	const names = $derived.by(() => {
		const shown = courseDisplayNames(
			sorted.map((c) => c.segment.name),
			park?.name ?? '',
		);
		return new Map(sorted.map((c, i) => [c.id, shown[i]]));
	});
	const hasLines = $derived(mapCourses.some((c) => c.points.length >= 2));
	// One quiet line for the park rather than "no time yet" on every card.
	const noTimesYet = $derived(
		auth.loggedIn && recordsLoaded && !recordsFailed && courses.length > 0 && !courses.some((c) => records.has(c.id)),
	);

	// The previewed course lives in `?course=`, written shallow so the list,
	// its scroll and the back target stay put; back from the course page,
	// a reload or a shared link brings the preview back.
	const shownUrl = () => page.shallow?.url ?? page.url;
	const selectedSlug = $derived(selectedCourseSlug(shownUrl().search, courses.map((c) => c.slug)));
	const selected = $derived(sorted.find((c) => c.slug === selectedSlug) ?? null);
	const selectedEnds = $derived.by(() => {
		if (!selected) return null;
		return courseEnds({
			line: pointsOf(selected),
			startGate: { lat: selected.segment.start_gate_lat, lng: selected.segment.start_gate_lng },
			endGate: { lat: selected.segment.end_gate_lat, lng: selected.segment.end_gate_lng },
			shape: selected.course_shape,
		});
	});
	const selectedStart = $derived(
		selected
			? startSentence(parseRouteGuide(selected.route_guide), {
					message: (key, params) => m(`parks.guide.${key}`, params),
					distance: formatDistance,
					short: formatElevation,
				})
			: null,
	);
	const legendItems = $derived.by<ParkMapLegendItem[]>(() => {
		if (!selected) return [{ kind: 'trailhead', label: m('parks.legendStart') }];
		if (selectedEnds && !selectedEnds.finish) return [{ kind: 'startFinish', label: m('parks.legendStartFinish') }];
		return [
			{ kind: 'start', label: m('parks.legendStart') },
			{ kind: 'finish', label: m('parks.legendFinish') },
		];
	});

	let previewHeading = $state<HTMLElement | null>(null);
	// The floating preview's height, kept clear at the foot of the page so it
	// never covers the last card or About this park.
	let previewHeight = $state(0);
	let mapFrame = $state<HTMLElement | null>(null);
	// Whether the map is drawn; its key shows only under a drawn map.
	let mapShown = $state(hasAcceptedConsent());

	function courseHref(slug: string): string {
		return `/parks/${data.region}/${data.park}/${slug}`;
	}

	function focusCard(slug: string) {
		document.querySelector<HTMLElement>(`[data-course-slug="${CSS.escape(slug)}"] .lc-tap`)?.focus();
	}

	// Opening a preview from none adds one history entry, so the browser's or
	// the phone's back closes it; picking another course replaces that entry.
	// `stacked` tells the back link to step over it.
	async function select(slug: string) {
		const opening = !selectedSlug;
		const url = shownUrl();
		await goto(`${url.pathname}${courseSearch(url.search, slug)}`, {
			shallow: true,
			replace: !opening,
			persistState: true,
			state: { ...page.state, stacked: opening ? 1 : (page.state.stacked ?? 0) },
		});
		await tick();
		previewHeading?.focus({ preventScroll: true });
		// On a phone the map is above the list, so bring the highlighted line
		// into view; the floating card keeps the course's name in sight.
		if (mapFrame && window.matchMedia('(max-width: 63.99rem)').matches) {
			const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
			const box = mapFrame.getBoundingClientRect();
			if (box.top < 0 || box.bottom > window.innerHeight) {
				mapFrame.scrollIntoView({ block: 'start', behavior: reduce ? 'auto' : 'smooth' });
			}
		}
	}

	function selectById(id: string) {
		const c = sorted.find((x) => x.id === id);
		if (c) void select(c.slug);
	}

	async function closePreview() {
		const from = selectedSlug;
		if (!from) return;
		if (page.state.stacked) {
			await new Promise<void>((done) => {
				addEventListener('popstate', () => done(), { once: true });
				history.back();
			});
		} else {
			const url = shownUrl();
			await goto(`${url.pathname}${courseSearch(url.search, null)}`, {
				shallow: true,
				replace: true,
				persistState: true,
				state: page.state,
			});
		}
		await tick();
		focusCard(from);
	}

	function onKeydown(e: KeyboardEvent) {
		if (e.key === 'Escape' && selected && !e.defaultPrevented) {
			e.preventDefault();
			void closePreview();
		}
	}

	async function loadRecords() {
		recordsFailed = false;
		if (!auth.loggedIn) return;
		try {
			records = await fetchParkCourseRecords();
			recordsLoaded = true;
		} catch (e) {
			console.error('park course records read failed', e);
			recordsFailed = true;
		}
	}

	async function loadMonthRunners(parkId: string) {
		monthRunnersFailed = false;
		if (!auth.loggedIn) return;
		try {
			monthRunners = await fetchParkCourseMonthRunners(parkId);
		} catch (e) {
			console.error('park course month runners read failed', e);
			monthRunnersFailed = true;
		}
	}

	async function load() {
		loading = true;
		loadFailed = false;
		try {
			const regionCode = regionCodeFromSlug(data.region);
			park = regionCode ? await fetchPark(regionCode, data.park) : null;
			courses = park ? await fetchParkCourses(park.id) : [];
		} catch (e) {
			console.error('park load failed', e);
			loadFailed = true;
		} finally {
			loading = false;
		}
		if (park && courses.length > 0) {
			void loadRecords();
			void loadMonthRunners(park.id);
		}
	}

	onMount(async () => {
		await auth.ready();
		await load();
	});
</script>

<svelte:head><title>{park?.name ?? m('parks.title')}</title></svelte:head>
<svelte:window onkeydown={onKeydown} />

<div class="page" style:--preview-space="{selected ? previewHeight : 0}px">
	<a href={back.href} onclick={back.handle} class="back-link" data-testid="park-back">
		<span class="material-symbols" aria-hidden="true">arrow_back</span>
		{m(BACK_PLACE_KEY[back.place])}
	</a>

	{#if loading}
		<p class="loading">&nbsp;</p>
	{:else if loadFailed}
		<EmptyState icon="error" tone="danger" title={m('parks.loadFailed')} role="alert" data-testid="park-load-error">
			{#snippet actions()}
				<button type="button" class="btn btn-outline" onclick={load}>{m('parks.retry')}</button>
			{/snippet}
		</EmptyState>
	{:else if !park}
		<EmptyState
			icon="park"
			title={m('parks.parkNotFoundTitle')}
			text={m('parks.parkNotFoundBody')}
			data-testid="park-not-found"
		/>
	{:else}
		{@const agencyKey = parkTypeKey(park.kind, park.agency)}
		<header class="detail-header">
			<h1>{park.name}</h1>
			<ul class="meta" data-testid="park-meta">
				<li>
					<span class="material-symbols" aria-hidden="true">place</span>
					{regionName(park.region_code)}
				</li>
				{#if agencyKey}<li>{m(agencyKey)}</li>{/if}
			</ul>
		</header>

		{#if courses.length === 0}
			<EmptyState icon="route" title={m('parks.noCourses')} data-testid="park-no-courses" />
		{:else}
			<div class="park-layout" class:with-map={hasLines}>
				<div class="side">
					{#if hasLines}
						<section class="overview" aria-label={m('parks.overviewMapLabel', { park: park.name })}>
							<div class="map-frame" bind:this={mapFrame}>
								<ParkCoursesMap
									courses={mapCourses}
									{highlightId}
									selectedId={selected?.id ?? null}
									{selectedEnds}
									onselect={selectById}
									label={m('parks.overviewMapLabel', { park: park.name })}
									twoFingerHint={m('parks.mapTwoFingers')}
									bind:consented={mapShown}
									testid="park-overview-map"
								/>
							</div>
							{#if mapShown}
								<ParkMapLegend testid="park-map-legend" items={legendItems} />
							{/if}
						</section>
					{/if}
					{#if selected}
						{@const shapeKey = labelKey(SHAPE_LABEL, selected.course_shape)}
						{@const laps = courseLapsChip(selected.laps)}
						{@const gain = Number(selected.segment.elevation_m)}
						{@const name = names.get(selected.id) ?? selected.segment.name}
						{@const difficultyKey = labelKey(DIFFICULTY_LABEL, selected.difficulty)}
						{@const statusKey = selected.status === 'open' ? null : labelKey(STATUS_LABEL, selected.status)}
						{@const closed = selected.status === 'closed'}
						{@const record = recordLine(selected.id)}
						{@const canSeeRoute = !!selected.route_id && courseOffersWayfinding(selected.status)}
						<section
							class="preview card-elevated"
							aria-labelledby="park-preview-title"
							data-testid="park-course-preview"
							bind:offsetHeight={previewHeight}
						>
							<div class="preview-head">
								<span class="preview-strip" style:background={colourOf.get(selected.id)} aria-hidden="true"></span>
								<h2 id="park-preview-title" class="preview-title" tabindex="-1" bind:this={previewHeading}>{name}</h2>
								{#if statusKey}
									<span class="status-pill" class:closed data-testid="park-course-preview-status">{m(statusKey)}</span>
								{/if}
								<button
									type="button"
									class="preview-close"
									aria-label={m('parks.previewClose')}
									onclick={() => void closePreview()}
									data-testid="park-course-preview-close"
								>
									<span class="material-symbols" aria-hidden="true">close</span>
								</button>
							</div>
							{#if closed}
								<p class="preview-closed" data-testid="park-course-preview-closed">
									{selected.status_note?.trim() || m('parks.closedBanner')}
								</p>
							{/if}
							<dl class="preview-facts">
								<div>
									<dt>{m('parks.statDistance')}</dt>
									<dd data-testid="park-course-preview-distance">{fmtCourseDistance(selected.segment.distance_m)}</dd>
								</div>
								{#if Number.isFinite(gain) && gain > 0}
									<div>
										<dt>{m('parks.statElevation')}</dt>
										<dd>{formatElevation(gain)}</dd>
									</div>
								{/if}
								{#if laps}
									<div>
										<dt>{m('parks.statLaps')}</dt>
										<dd data-testid="park-course-preview-laps">
											{m('parks.lapsOf', { n: laps, distance: fmtCourseDistance(Number(selected.segment.distance_m) / laps) })}
										</dd>
									</div>
								{/if}
								{#if shapeKey}
									<div>
										<dt>{m('parks.statShape')}</dt>
										<dd data-testid="park-course-preview-shape">{m(shapeKey)}</dd>
									</div>
								{/if}
								{#if difficultyKey}
									<div>
										<dt>{m('parks.statDifficulty')}</dt>
										<dd>{m(difficultyKey)}</dd>
									</div>
								{/if}
							</dl>
							{#if record}
								<p class="preview-record" data-testid="park-course-preview-record">
									<span class="material-symbols" aria-hidden="true">emoji_events</span>
									{record}
								</p>
							{/if}
							{#if selectedStart && !closed}
								<p class="preview-start">
									<span class="material-symbols" aria-hidden="true">place</span>
									<span lang={selectedStart.lang ?? undefined} data-testid="park-course-preview-start">{selectedStart.text}</span>
								</p>
							{/if}
							<div class="preview-actions">
								{#if canSeeRoute}
									<!-- The web records no runs, so the phone's Run this course is
									     See the route here, as on the course page. -->
									<a class="btn btn-primary preview-action" href="/routes/{selected.route_id}" data-testid="park-course-preview-route">
										<span class="material-symbols" aria-hidden="true">route</span>
										{m('parks.seeRoute')}
									</a>
								{/if}
								<a
									class="btn preview-action"
									class:btn-primary={!canSeeRoute}
									class:btn-outline={canSeeRoute}
									href={courseHref(selected.slug)}
									data-testid="park-course-preview-open"
								>
									<span class="material-symbols" aria-hidden="true">emoji_events</span>
									{m('parks.board')}
								</a>
							</div>
						</section>
					{/if}
				</div>

				<section class="courses" aria-labelledby="park-courses-title">
					<div class="courses-head">
						<SectionHeader title label={m('parks.coursesTitle')} id="park-courses-title">
							{#snippet badge()}
								<span class="count">{m('parks.courseCount', { n: courses.length })}</span>
							{/snippet}
						</SectionHeader>
						<p class="list-note" id="park-preview-hint">{m('parks.previewHint')}</p>
					</div>
					<ul class="course-list" data-testid="park-courses">
						{#each sorted as course (course.id)}
							{@const shapeKey = courseShapeShown(course.course_shape) ? labelKey(SHAPE_LABEL, course.course_shape) : null}
							{@const statusKey = labelKey(STATUS_LABEL, course.status)}
							{@const difficultyKey = labelKey(DIFFICULTY_LABEL, course.difficulty)}
							{@const laps = courseLapsChip(course.laps)}
							{@const record = recordLine(course.id)}
							{@const ranThisMonth = monthRunners.get(course.id) ?? 0}
							{@const name = names.get(course.id) ?? course.segment.name}
							<li
								data-course-slug={course.slug}
								onmouseenter={() => (highlightId = course.id)}
								onmouseleave={() => (highlightId = null)}
								onfocusin={() => (highlightId = course.id)}
								onfocusout={() => (highlightId = null)}
							>
								<ListCard
									onclick={() => void select(course.slug)}
									selected={selected?.id === course.id}
									title={name}
									class="course-card{course.status === 'closed' ? ' closed' : ''}"
									testid="park-course-card"
								>
									{#snippet leading()}
										<span class="strip" style:background={colourOf.get(course.id)} aria-hidden="true"></span>
									{/snippet}
									{#snippet meta()}
										<span class="stats" data-testid="park-course-stats">
											<span class="distance" data-testid="park-course-distance">{fmtCourseDistance(course.segment.distance_m)}</span
											>{#each statsAfterDistance(course) as fact (fact)}&nbsp;·&nbsp;{fact}{/each}
										</span>
										{#if laps || shapeKey || difficultyKey || course.status !== 'open'}
											<span class="facts">
												{#if laps}<span class="chip" data-testid="park-course-laps">{m('parks.lapsChip', { n: laps })}</span>{/if}
												{#if shapeKey}<span class="chip">{m(shapeKey)}</span>{/if}
												{#if difficultyKey}<span class="chip">{m(difficultyKey)}</span>{/if}
												{#if course.status !== 'open' && statusKey}
													<span class="status-pill" class:closed={course.status === 'closed'}>{m(statusKey)}</span>
												{/if}
											</span>
										{/if}
										{#if record}
											<span class="course-record" data-testid="park-course-record">
												<span class="material-symbols" aria-hidden="true">emoji_events</span>
												{record}
											</span>
										{/if}
										{#if ranThisMonth > 0}
											<span class="course-record" data-testid="park-course-month-runners">
												<span class="material-symbols month-icon" aria-hidden="true">calendar_month</span>
												{m('parks.monthRunners', { n: ranThisMonth })}
											</span>
										{/if}
									{/snippet}
								</ListCard>
							</li>
						{/each}
					</ul>
					<!-- Below the cards, so a line that arrives late never moves a card
					     under a finger about to tap it. -->
					{#if noTimesYet}
						<p class="list-note">
							<span class="material-symbols" aria-hidden="true">emoji_events</span>
							<span data-testid="park-no-times-yet">{m('parks.noTimesYet')}</span>
						</p>
					{/if}
					{#if recordsFailed}
						<p class="records-failed" role="status" data-testid="park-records-failed">
							{m('races.anyTimeFastestFailed')}
						</p>
					{/if}
					{#if monthRunnersFailed}
						<p class="records-failed" role="status" data-testid="park-month-runners-failed">
							{m('parks.monthRunnersFailed')}
							<button type="button" class="btn btn-outline btn-sm" onclick={() => park && void loadMonthRunners(park.id)}>
								{m('parks.retry')}
							</button>
						</p>
					{/if}
				</section>
			</div>
		{/if}
		<!-- The park's own words and link, and the notices park_courses.md
		     requires on every park page, folded into one row at the end. -->
		<details class="about" data-testid="park-about">
			<summary data-testid="park-about-toggle">
				<span class="material-symbols" aria-hidden="true">info</span>
				{m('parks.aboutPark')}
			</summary>
			<div class="about-body">
				{#if park.description}<p class="description">{park.description}</p>{/if}
				{#if park.website_url}
					<p>
						<a class="website" href={park.website_url} target="_blank" rel="noopener noreferrer" data-testid="park-website">
							{m('parks.website')}
							<span class="material-symbols" aria-hidden="true">open_in_new</span>
						</a>
					</p>
				{/if}
				<p class="not-affiliated" data-testid="park-not-affiliated">{m('parks.notAffiliated')}</p>
				<p class="not-affiliated" data-testid="park-group-permit">{m('parks.groupPermitNotice')}</p>
			</div>
		</details>
	{/if}
</div>

<style>
	.page {
		padding: var(--page-padding-y) var(--page-padding-x);
		padding-bottom: calc(var(--page-padding-y) + var(--preview-space, 0px));
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
	.loading {
		min-height: 40vh;
	}
	.detail-header {
		margin-bottom: var(--space-md);
	}
	.detail-header h1 {
		margin: 0 0 var(--space-xs);
		overflow-wrap: anywhere;
	}
	.meta {
		list-style: none;
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-xs) var(--space-sm);
		margin: 0;
		padding: 0;
		color: var(--color-text-secondary);
		font-size: 0.9rem;
	}
	.meta li {
		display: inline-flex;
		align-items: center;
		gap: 0.25rem;
	}
	/* The dot ends an item rather than starting the next, so a wrapped line
	   never opens on one. */
	.meta li:not(:last-child)::after {
		content: '·';
		margin-inline-start: var(--space-sm);
		color: var(--color-text-tertiary);
	}
	.meta .material-symbols {
		font-size: 1rem;
	}
	.park-layout {
		display: grid;
		grid-template-columns: minmax(0, 1fr);
		gap: var(--space-lg);
	}
	/* About two fifths of a phone's screen, so the courses start under it. */
	.map-frame {
		height: clamp(14rem, 40dvh, 28rem);
	}
	@media (min-width: 64rem) {
		.park-layout.with-map {
			grid-template-columns: minmax(0, 5fr) minmax(0, 6fr);
			align-items: start;
		}
		.park-layout.with-map .side {
			grid-column: 2;
			grid-row: 1;
			position: sticky;
			top: var(--space-md);
		}
		.park-layout.with-map .courses {
			grid-column: 1;
			grid-row: 1;
		}
		.map-frame {
			height: min(32rem, 60vh);
		}
	}
	.count {
		font-size: 0.85rem;
		font-weight: 400;
		color: var(--color-text-tertiary);
	}
	.records-failed {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-sm);
		margin: var(--space-sm) 0 0;
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}
	.course-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: grid;
		gap: var(--space-sm);
	}
	.course-list > li {
		min-width: 0;
	}
	/* The whole name, wrapped, never cut: the card is the place a long
	   catalogue name is read. */
	.course-list :global(.course-card .list-card-title) {
		font-size: 1.05rem;
		overflow-wrap: anywhere;
	}
	.course-list :global(.course-card .lc-leading) {
		align-self: stretch;
	}
	.strip {
		display: block;
		width: 0.4rem;
		height: 100%;
		min-height: 3rem;
		border-radius: var(--radius-pill);
	}
	.list-note {
		display: flex;
		align-items: center;
		gap: var(--space-xs);
		margin: 0 0 var(--space-sm);
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}
	.course-list ~ .list-note {
		margin: var(--space-sm) 0 0;
	}
	.list-note .material-symbols {
		flex-shrink: 0;
		font-size: 1rem;
		color: var(--color-crown);
	}
	.course-list :global(.course-card.closed .list-card-title) {
		opacity: 0.6;
	}
	.stats {
		display: block;
		margin-top: var(--space-2xs);
	}
	.distance {
		font-weight: 600;
		color: var(--color-text);
		font-variant-numeric: tabular-nums;
	}
	.facts {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 0.25rem var(--space-sm);
		margin-top: var(--space-2xs);
		font-size: 0.85rem;
	}
	.chip {
		padding: 0.05rem 0.5rem;
		border-radius: var(--radius-pill);
		background: var(--chip-bg);
		color: var(--chip-fg);
		font-size: 0.8rem;
		font-weight: 600;
	}
	.course-record {
		display: flex;
		margin-top: var(--space-2xs);
		align-items: center;
		gap: 0.25rem;
		font-size: 0.9rem;
		color: var(--color-text-secondary);
	}
	.course-record .material-symbols {
		flex-shrink: 0;
		font-size: 1rem;
		color: var(--color-crown);
	}
	.course-record .month-icon {
		color: var(--color-text-tertiary);
	}
	.status-pill {
		padding: 0.1rem 0.5rem;
		border-radius: var(--radius-pill);
		font-size: 0.8rem;
		background: var(--color-bg-secondary);
	}
	.status-pill.closed {
		color: var(--color-danger-text);
	}
	.about {
		max-width: var(--page-measure);
		margin-top: var(--space-xl);
		border-top: 1px solid var(--color-border);
	}
	.about summary {
		display: flex;
		align-items: center;
		gap: var(--space-xs);
		min-height: var(--tap-target-min);
		cursor: pointer;
		font-weight: 600;
	}
	.about summary .material-symbols {
		font-size: 1.1rem;
		color: var(--color-text-secondary);
	}
	.about-body > p {
		margin: 0 0 var(--space-sm);
	}
	.description {
		color: var(--color-text-secondary);
		line-height: 1.5;
	}
	.website {
		display: inline-flex;
		align-items: center;
		gap: 0.2rem;
		min-height: var(--tap-target-min);
	}
	.not-affiliated {
		font-size: 0.8rem;
		color: var(--color-text-tertiary);
		line-height: 1.5;
	}
	/* Below 64rem the preview floats over the foot of the screen: the list
	   stays where it was and a tap on another card swaps the course. */
	@media (max-width: 63.99rem) {
		.preview {
			position: fixed;
			inset: auto 0 0 0;
			z-index: var(--z-modal);
			max-height: 70dvh;
			overflow-y: auto;
			padding: var(--space-md) var(--space-md) calc(var(--space-md) + env(safe-area-inset-bottom));
			border-radius: var(--radius-lg) var(--radius-lg) 0 0;
			box-shadow: var(--shadow-lg);
		}
	}
	.preview-closed {
		margin: 0;
		color: var(--color-danger-text);
		line-height: 1.45;
	}
	.preview-actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-sm);
	}
	.preview {
		margin-top: var(--space-md);
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.preview-head {
		display: flex;
		align-items: flex-start;
		gap: var(--space-sm);
	}
	.preview-strip {
		flex-shrink: 0;
		align-self: stretch;
		width: 0.4rem;
		border-radius: var(--radius-pill);
	}
	.preview-title {
		flex: 1;
		margin: 0;
		font-size: var(--font-size-section-title);
		font-weight: 700;
		line-height: 1.3;
		align-self: center;
		overflow-wrap: anywhere;
	}
	.preview-title:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}
	.preview-close {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		flex-shrink: 0;
		width: var(--tap-target-min);
		height: var(--tap-target-min);
		margin: calc(var(--space-sm) * -1) calc(var(--space-sm) * -1) 0 0;
		border: 0;
		border-radius: var(--radius-pill);
		background: none;
		color: var(--color-text-secondary);
		cursor: pointer;
	}
	.preview-close:hover {
		background: var(--color-fill-subtle);
	}
	.preview-close:focus-visible {
		outline: 2px solid var(--color-primary);
	}
	.preview-facts {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-sm) var(--space-lg);
		margin: 0;
	}
	.preview-facts dt {
		font-size: 0.8rem;
		color: var(--color-text-secondary);
	}
	.preview-facts dd {
		margin: 0;
		font-weight: 600;
		font-variant-numeric: tabular-nums;
	}
	.preview-record,
	.preview-start {
		display: flex;
		align-items: flex-start;
		gap: var(--space-xs);
		margin: 0;
		color: var(--color-text);
		line-height: 1.45;
	}
	.preview-record .material-symbols {
		flex-shrink: 0;
		font-size: 1.1rem;
		color: var(--color-crown);
		margin-top: 0.1rem;
	}
	.preview-start .material-symbols {
		flex-shrink: 0;
		font-size: 1.1rem;
		color: var(--color-text-secondary);
		margin-top: 0.1rem;
	}
	.preview-action {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		gap: var(--space-xs);
		min-height: var(--tap-target-min);
	}
	@media (max-width: 40rem) {
		.preview-action {
			flex: 1 1 100%;
		}
	}
</style>
