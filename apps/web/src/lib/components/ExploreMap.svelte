<script lang="ts">
	// The map behind Routes → Explore and Explore segments (decisions § 2611):
	// start pins with a 44 px tap target, clustered where they crowd, and the
	// lines the page hands it. It owns no data. A tap reports every pin or line
	// under the finger through `onpick`, so the page can open the one it hit or
	// ask "Which route?" when several overlap; a small cluster reports its
	// routes the same way and a big one zooms in. It opens on the best place it
	// knows and moves to a better one as it arrives, until the reader moves it
	// (decisions § 2613, `map_view_memory.ts`).
	import type * as GeoJSON from 'geojson';
	import { onDestroy, onMount, untrack } from 'svelte';
	import maplibregl from '#lib/routes/maplibre.ts';
	import 'maplibre-gl/dist/maplibre-gl.css';
	import { PUBLIC_MAPTILER_KEY as PUBLIC_MAPTILER_KEY_ENV } from '$app/env/public';
	import { basemapIsDarkFromEnv, mapStyleUrlFromEnv } from '#lib/routes/map-style.svelte.ts';
	import {
		mapAccentColour,
		mapLabelInk,
		mapOverlayOutline,
		mapPinnedLine,
		mapStartColour,
	} from '#lib/routes/basemap_contrast.ts';
	import { watchMapResize } from '#lib/routes/map_resize.ts';
	import { hasAcceptedConsent } from '#lib/settings/consent.svelte.ts';
	import { m } from '#lib/i18n/store.svelte.ts';
	import type { ExploreLine, ExplorePin, LatLng, ViewBounds } from '#lib/routes/explore_viewport.ts';
	import { loadMapView, opensOn, quietFix, saveMapView, type MapOpening } from '#lib/routes/map_view_memory.ts';

	const PUBLIC_MAPTILER_KEY = PUBLIC_MAPTILER_KEY_ENV ?? '';

	interface Props {
		pins: ExplorePin[];
		lines?: ExploreLine[];
		selectedId?: string | null;
		label: string;
		onmove: (bounds: ViewBounds, center: LatLng) => void;
		onpick: (ids: string[]) => void;
		/// The browser-storage key this map remembers its last view under. A
		/// map with one also opens on the reader when location is already
		/// granted; a map without one opens on the world for the page to frame.
		memoryKey?: string;
		testid?: string;
	}

	let { pins, lines = [], selectedId = null, label, onmove, onpick, memoryKey, testid }: Props = $props();

	let openedOn: MapOpening = 'world';
	let touched = false;

	/// A cluster this small opens as a "Which route?" list; a bigger one zooms in.
	const PICK_CLUSTER_MAX = 6;

	const PINS = 'explore-pins';
	const LINES = 'explore-lines';
	const LINE_CASING = 'explore-line-casing';
	const LINE = 'explore-line';
	const LINE_HIT = 'explore-line-hit';
	const CLUSTER = 'explore-cluster';
	const CLUSTER_COUNT = 'explore-cluster-count';
	const PIN = 'explore-pin';
	const PIN_HIT = 'explore-pin-hit';

	const prefersDark = typeof window !== 'undefined' && window.matchMedia('(prefers-color-scheme: dark)').matches;
	const darkBasemap = basemapIsDarkFromEnv(PUBLIC_MAPTILER_KEY, prefersDark);

	let consented = $state(untrack(() => hasAcceptedConsent()));
	let mapEl: HTMLDivElement | undefined = $state();
	let map: maplibregl.Map | null = null;
	let ready = $state(false);
	let stopResize: (() => void) | null = null;

	function pinData(): GeoJSON.FeatureCollection {
		return {
			type: 'FeatureCollection',
			features: pins.map((p) => ({
				type: 'Feature',
				properties: { id: p.id, name: p.name },
				geometry: { type: 'Point', coordinates: [p.lng, p.lat] },
			})),
		};
	}

	function lineData(): GeoJSON.FeatureCollection {
		return {
			type: 'FeatureCollection',
			features: lines
				.filter((l) => l.coords.length > 1)
				.map((l) => ({
					type: 'Feature',
					properties: { id: l.id },
					geometry: { type: 'LineString', coordinates: l.coords },
				})),
		};
	}

	function emitMove() {
		if (!map) return;
		const b = map.getBounds();
		const c = map.getCenter();
		if (memoryKey) saveMapView(memoryKey, { lat: c.lat, lng: c.lng, zoom: map.getZoom() });
		onmove({ west: b.getWest(), south: b.getSouth(), east: b.getEast(), north: b.getNorth() }, { lat: c.lat, lng: c.lng });
	}

	/// Selected pin and line stand out; with one selected the rest dim.
	function paintSelection() {
		if (!map || !ready) return;
		const sel = selectedId ?? '';
		const isSel: maplibregl.ExpressionSpecification = ['==', ['get', 'id'], sel];
		const rest = selectedId ? 0.35 : 0.95;
		map.setPaintProperty(PIN, 'circle-opacity', ['case', isSel, 1, rest]);
		map.setPaintProperty(PIN, 'circle-radius', ['case', isSel, 11, 8]);
		map.setPaintProperty(PIN, 'circle-color', ['case', isSel, mapStartColour(darkBasemap), mapAccentColour(darkBasemap)]);
		map.setPaintProperty(PIN, 'circle-stroke-width', ['case', isSel, 3, 2]);
		map.setPaintProperty(LINE, 'line-opacity', ['case', isSel, 1, selectedId ? 0.3 : 0.85]);
		map.setPaintProperty(LINE, 'line-width', ['case', isSel, 5, 3]);
		map.setPaintProperty(CLUSTER, 'circle-opacity', selectedId ? 0.35 : 0.92);
	}

	function startMap() {
		if (map || !mapEl) return;
		const remembered = memoryKey ? loadMapView(memoryKey) : null;
		if (remembered) openedOn = 'remembered';
		map = new maplibregl.Map({
			container: mapEl,
			style: mapStyleUrlFromEnv(PUBLIC_MAPTILER_KEY, prefersDark),
			center: remembered ? [remembered.lng, remembered.lat] : [0, 30],
			zoom: remembered ? remembered.zoom : 2,
		});
		// A drag, pinch, wheel or keyboard move carries the DOM event that
		// caused it; a move this map or the page makes does not.
		map.on('movestart', (e) => {
			if ((e as { originalEvent?: unknown }).originalEvent) touched = true;
		});
		// Only a map that remembers its view opens on the reader: one that
		// frames what it shows (Explore segments) keeps that framing.
		if (memoryKey) void quietFix().then((at) => {
			if (!at || !map || !opensOn(openedOn, 'here', touched)) return;
			openedOn = 'here';
			map.jumpTo({ center: [at.lng, at.lat], zoom: 12 });
		});
		stopResize = watchMapResize(mapEl, map);
		if (import.meta.env.DEV && typeof window !== 'undefined') {
			(window as unknown as { __exploreMap?: unknown }).__exploreMap = map;
		}
		map.addControl(new maplibregl.NavigationControl({ showCompass: false }), 'top-right');
		map.on('load', () => {
			if (!map) return;
			map.addSource(LINES, { type: 'geojson', data: lineData() });
			map.addLayer({
				id: LINE_CASING,
				type: 'line',
				source: LINES,
				layout: { 'line-cap': 'round', 'line-join': 'round' },
				paint: { 'line-color': mapOverlayOutline(darkBasemap), 'line-width': 7, 'line-opacity': 0.4 },
			});
			map.addLayer({
				id: LINE,
				type: 'line',
				source: LINES,
				layout: { 'line-cap': 'round', 'line-join': 'round' },
				paint: { 'line-color': mapPinnedLine(darkBasemap), 'line-width': 3, 'line-opacity': 0.85 },
			});
			map.addLayer({
				id: LINE_HIT,
				type: 'line',
				source: LINES,
				paint: { 'line-color': mapPinnedLine(darkBasemap), 'line-width': 22, 'line-opacity': 0 },
			});
			map.addSource(PINS, {
				type: 'geojson',
				data: pinData(),
				cluster: true,
				clusterRadius: 40,
				clusterMaxZoom: 14,
			});
			map.addLayer({
				id: CLUSTER,
				type: 'circle',
				source: PINS,
				filter: ['has', 'point_count'],
				paint: {
					'circle-color': mapAccentColour(darkBasemap),
					'circle-opacity': 0.92,
					'circle-stroke-color': mapOverlayOutline(darkBasemap),
					'circle-stroke-width': 2,
					'circle-radius': ['step', ['get', 'point_count'], 16, 10, 20, 25, 24],
				},
			});
			map.addLayer({
				id: CLUSTER_COUNT,
				type: 'symbol',
				source: PINS,
				filter: ['has', 'point_count'],
				layout: {
					'text-field': ['get', 'point_count_abbreviated'],
					'text-font': ['Noto Sans Regular'],
					'text-size': 13,
				},
				paint: { 'text-color': mapLabelInk(darkBasemap) },
			});
			map.addLayer({
				id: PIN,
				type: 'circle',
				source: PINS,
				filter: ['!', ['has', 'point_count']],
				paint: {
					'circle-color': mapAccentColour(darkBasemap),
					'circle-radius': 8,
					'circle-stroke-color': mapOverlayOutline(darkBasemap),
					'circle-stroke-width': 2,
					'circle-opacity': 0.95,
				},
			});
			// The visible dot is 16 px; this invisible ring is the 44 px finger target.
			map.addLayer({
				id: PIN_HIT,
				type: 'circle',
				source: PINS,
				filter: ['!', ['has', 'point_count']],
				paint: { 'circle-radius': 22, 'circle-opacity': 0, 'circle-stroke-width': 0 },
			});
			for (const layer of [PIN_HIT, CLUSTER, LINE_HIT]) {
				map.on('mouseenter', layer, () => map && (map.getCanvas().style.cursor = 'pointer'));
				map.on('mouseleave', layer, () => map && (map.getCanvas().style.cursor = ''));
			}
			map.on('click', (e) => void onTap(e.point));
			map.on('moveend', emitMove);
			ready = true;
			paintSelection();
			emitMove();
		});
	}

	async function onTap(point: maplibregl.PointLike) {
		if (!map) return;
		const hits = map.queryRenderedFeatures(point, { layers: [CLUSTER, PIN_HIT, LINE_HIT] });
		const cluster = hits.find((f) => f.layer.id === CLUSTER);
		if (cluster) {
			const src = map.getSource(PINS) as maplibregl.GeoJSONSource | undefined;
			const clusterId = cluster.properties?.cluster_id as number | undefined;
			const count = (cluster.properties?.point_count as number | undefined) ?? 0;
			if (!src || clusterId == null) return;
			try {
				if (count <= PICK_CLUSTER_MAX) {
					const leaves = await src.getClusterLeaves(clusterId, PICK_CLUSTER_MAX, 0);
					onpick(leaves.map((l) => l.properties?.id as string).filter(Boolean));
				} else {
					const zoom = await src.getClusterExpansionZoom(clusterId);
					const center = (cluster.geometry as GeoJSON.Point).coordinates as [number, number];
					map.easeTo({ center, zoom });
				}
			} catch (err) {
				console.warn('explore cluster lookup failed', err);
			}
			return;
		}
		const ids = [...new Set(hits.map((f) => f.properties?.id as string | undefined).filter((id): id is string => !!id))];
		if (ids.length > 0) onpick(ids);
	}

	export function zoomOut() {
		touched = true;
		map?.easeTo({ zoom: Math.max(1, map.getZoom() - 2) });
	}

	export function flyTo(at: LatLng, zoom = 13) {
		touched = true;
		map?.flyTo({ center: [at.lng, at.lat], zoom });
	}

	/// Frames a line, leaving room at the bottom for the card over the map.
	export function fitLine(coords: [number, number][]) {
		if (!map || coords.length === 0) return;
		touched = true;
		const bounds = new maplibregl.LngLatBounds(coords[0], coords[0]);
		for (const c of coords) bounds.extend(c);
		map.fitBounds(bounds, { padding: { top: 72, bottom: 220, left: 40, right: 40 }, maxZoom: 15 });
	}

	$effect(() => {
		void pins;
		if (!ready || !map) return;
		(map.getSource(PINS) as maplibregl.GeoJSONSource | undefined)?.setData(pinData());
	});

	$effect(() => {
		void lines;
		if (!ready || !map) return;
		(map.getSource(LINES) as maplibregl.GeoJSONSource | undefined)?.setData(lineData());
	});

	$effect(() => {
		void selectedId;
		paintSelection();
	});

	function loadMapNow() {
		consented = true;
		queueMicrotask(startMap);
	}

	onMount(() => {
		if (consented) startMap();
	});

	onDestroy(() => {
		if (import.meta.env.DEV && typeof window !== 'undefined') {
			(window as unknown as { __exploreMap?: unknown }).__exploreMap = undefined;
		}
		stopResize?.();
		map?.remove();
		map = null;
	});
</script>

<div class="explore-map" data-testid={testid}>
	<div bind:this={mapEl} class="canvas" role="region" aria-label={label}></div>
	{#if !consented}
		<!-- audit/cookie-consent: MapTiler logs the requester IP per tile, so the
		     basemap loads only after the visitor opts in. -->
		<div class="consent" data-testid="explore-map-consent">
			<div class="consent-card">
				<h3>{m('runMap.consentTitle')}</h3>
				<p>
					{m('runMap.consentPrefix')}<strong>MapTiler</strong>{m('runMap.consentMiddle')}<strong
						>{m('runMap.loadMap')}</strong
					>{m('runMap.consentBeforeLink')}<a href="/cookie-notice">{m('runMap.cookieNotice')}</a>{m(
						'runMap.consentSuffix',
					)}
				</p>
				<button type="button" class="btn btn-primary" onclick={loadMapNow}>{m('runMap.loadMap')}</button>
			</div>
		</div>
	{/if}
</div>

<style>
	.explore-map {
		position: absolute;
		inset: 0;
	}
	.canvas {
		position: absolute;
		inset: 0;
	}
	.consent {
		position: absolute;
		inset: 0;
		display: flex;
		align-items: center;
		justify-content: center;
		padding: var(--space-md);
		background: var(--color-bg-secondary);
	}
	.consent-card {
		max-width: 26rem;
		padding: var(--space-lg);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		background: var(--color-surface);
		text-align: center;
	}
	.consent-card h3 {
		margin-bottom: var(--space-sm);
	}
	.consent-card p {
		margin-bottom: var(--space-md);
		font-size: 0.9rem;
		color: var(--color-text-secondary);
	}
</style>
