<script lang="ts">
	// Every park on one map (decisions § 2612): a pill per park with its course
	// count in a green circle and its name, a link to the park. The pills are
	// real links in the DOM, so a keyboard, a screen reader and a crawler reach
	// every park the map shows. The camera frames the parks shown until the
	// reader moves the map; every settled view reports its bounds so the page
	// can count the parks in it.
	import { onDestroy, untrack } from 'svelte';
	import { m } from '#lib/i18n/store.svelte.ts';
	import maplibregl from '#lib/routes/maplibre.ts';
	import 'maplibre-gl/dist/maplibre-gl.css';
	import { PUBLIC_MAPTILER_KEY as PUBLIC_MAPTILER_KEY_ENV } from '$app/env/public';
	import { mapStyleUrlFromEnv as mapStyleUrl } from '#lib/routes/map-style.svelte.ts';
	import { watchMapResize } from '#lib/routes/map_resize.ts';
	import { hasAcceptedConsent } from '#lib/settings/consent.svelte.ts';
	import type { LatLng, MapBounds } from '#lib/parks/park_map.ts';

	const PUBLIC_MAPTILER_KEY = PUBLIC_MAPTILER_KEY_ENV ?? '';

	export interface ParkPin {
		id: string;
		href: string;
		name: string;
		count: number;
		point: LatLng;
	}

	interface Props {
		parks: ParkPin[];
		label: string;
		onview?: (bounds: MapBounds) => void;
		consented?: boolean;
		testid?: string;
	}

	let { parks, label, onview, consented = $bindable(untrack(() => hasAcceptedConsent())), testid }: Props = $props();

	const prefersDark = typeof window !== 'undefined' && window.matchMedia('(prefers-color-scheme: dark)').matches;
	const reducedMotion =
		typeof window !== 'undefined' && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

	let container: HTMLDivElement | undefined = $state();
	let map: maplibregl.Map | null = null;
	let ready = false;
	let readerMoved = false;
	let stopResize: (() => void) | null = null;
	let markers: maplibregl.Marker[] = [];

	function pill(p: ParkPin): HTMLAnchorElement {
		const a = document.createElement('a');
		a.className = 'park-pin';
		a.href = p.href;
		a.dataset.testid = 'parks-map-pin';
		a.setAttribute('aria-label', m('parks.markerLabel', { park: p.name, count: m('parks.courseCount', { n: p.count }) }));
		const count = document.createElement('span');
		count.className = 'park-pin-count';
		count.setAttribute('aria-hidden', 'true');
		count.textContent = String(p.count);
		const name = document.createElement('span');
		name.className = 'park-pin-name';
		name.setAttribute('aria-hidden', 'true');
		name.textContent = p.name;
		a.append(count, name);
		return a;
	}

	function placePins() {
		for (const marker of markers) marker.remove();
		markers = [];
		if (!map) return;
		for (const p of parks) {
			markers.push(
				new maplibregl.Marker({ element: pill(p), anchor: 'bottom' }).setLngLat([p.point.lng, p.point.lat]).addTo(map),
			);
		}
	}

	function frame(animate: boolean) {
		if (!map || parks.length === 0) return;
		const box = map.getContainer();
		if (box.clientWidth === 0 || box.clientHeight === 0) return;
		let w = Infinity;
		let s = Infinity;
		let e = -Infinity;
		let n = -Infinity;
		for (const p of parks) {
			w = Math.min(w, p.point.lng);
			e = Math.max(e, p.point.lng);
			s = Math.min(s, p.point.lat);
			n = Math.max(n, p.point.lat);
		}
		const pad = Math.max(24, Math.min(80, Math.round(Math.min(box.clientWidth, box.clientHeight) / 6)));
		map.fitBounds(
			[
				[w, s],
				[e, n],
			],
			{ padding: pad, maxZoom: 12, duration: animate && !reducedMotion ? 600 : 0 },
		);
	}

	function report() {
		if (!map || !onview) return;
		const b = map.getBounds();
		onview({ south: b.getSouth(), west: b.getWest(), north: b.getNorth(), east: b.getEast() });
	}

	/** Centres the map on a place the reader asked for (Near me). */
	export function showPlace(point: LatLng) {
		if (!map) return;
		readerMoved = true;
		map.flyTo({ center: [point.lng, point.lat], zoom: 9, duration: reducedMotion ? 0 : 800 });
	}

	$effect(() => {
		if (!consented || !container || map) return;
		map = new maplibregl.Map({
			container,
			style: mapStyleUrl(PUBLIC_MAPTILER_KEY, prefersDark),
			center: [-78, 38],
			zoom: 4,
		});
		map.addControl(new maplibregl.NavigationControl({ showCompass: false }), 'bottom-right');
		stopResize = watchMapResize(container, map);
		for (const kind of ['dragstart', 'zoomstart', 'rotatestart', 'pitchstart'] as const) {
			map.on(kind, (e: { originalEvent?: Event }) => {
				if (e.originalEvent) readerMoved = true;
			});
		}
		map.on('resize', () => {
			if (!readerMoved) frame(false);
		});
		map.on('moveend', report);
		map.on('load', () => {
			ready = true;
			placePins();
			frame(false);
			report();
		});
	});

	$effect(() => {
		void parks;
		untrack(() => {
			if (!ready) return;
			placePins();
			if (!readerMoved) frame(true);
			report();
		});
	});

	onDestroy(() => {
		stopResize?.();
		for (const marker of markers) marker.remove();
		map?.remove();
	});
</script>

{#if consented}
	<div class="parks-map" bind:this={container} role="region" aria-label={label} data-testid={testid}></div>
{:else}
	<!-- audit/cookie-consent: MapTiler logs the requester IP per tile fetch, so
	     the map waits for consent or an explicit "Load map", as RunMap does. -->
	<div class="parks-map-consent" data-testid={testid ? `${testid}-consent` : undefined}>
		<p>
			{m('runMap.consentPrefix')}<strong>MapTiler</strong>{m('runMap.consentMiddle')}<strong>{m('runMap.loadMap')}</strong>{m('runMap.consentBeforeLink')}<a href="/cookie-notice">{m('runMap.cookieNotice')}</a>{m('runMap.consentSuffix')}
		</p>
		<button type="button" class="btn btn-secondary btn-sm" onclick={() => (consented = true)}>
			{m('runMap.loadMap')}
		</button>
	</div>
{/if}

<style>
	.parks-map {
		width: 100%;
		height: 100%;
	}
	.parks-map-consent {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		justify-content: center;
		gap: var(--space-sm);
		height: 100%;
		box-sizing: border-box;
		padding: var(--space-xl) var(--space-md);
		background: var(--color-bg-secondary);
	}
	.parks-map-consent p {
		margin: 0;
		max-width: var(--page-measure);
	}
	:global(.park-pin) {
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
		max-width: 14rem;
		min-height: var(--tap-target-min);
		box-sizing: border-box;
		padding: var(--space-2xs) var(--space-sm) var(--space-2xs) var(--space-2xs);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-pill);
		background: var(--color-surface);
		box-shadow: var(--shadow-md);
		color: var(--color-text);
		font-size: 0.85rem;
		font-weight: 600;
		line-height: 1.2;
		text-decoration: none;
	}
	:global(.park-pin:hover) {
		border-color: var(--color-primary);
	}
	:global(.park-pin:focus-visible) {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
		z-index: 2;
	}
	:global(.park-pin-count) {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		flex-shrink: 0;
		min-width: 1.6rem;
		height: 1.6rem;
		padding: 0 0.3rem;
		box-sizing: border-box;
		border-radius: var(--radius-pill);
		/* White on --color-success-strong is 5.13:1, as the success toast. */
		background: var(--color-success-strong);
		color: white;
		font-variant-numeric: tabular-nums;
	}
	:global(.park-pin-name) {
		overflow-wrap: anywhere;
	}
</style>
