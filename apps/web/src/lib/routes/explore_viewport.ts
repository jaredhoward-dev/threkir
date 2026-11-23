// What Routes → Explore lists: the routes (or segments) inside the map's
// current view, narrowed by the Filters sheet and ordered by the list page's
// sort chip (decisions § 2611). Pure, so the web and the phone order and count
// the same rows; the Dart twin is `apps/mobile_android/lib/explore_viewport.dart`.

import { haversineMetres } from '#lib/geo/haversine.ts';
import { compareFoldedNames } from '#lib/segments/catalogue_browse.ts';

/** One thing on the map: a route's start pin, or a segment's start. */
export interface ExplorePin {
	id: string;
	name: string;
	lat: number;
	lng: number;
	distanceM: number;
	surface: string;
	featured: boolean;
	runCount: number;
}

/** A line on the map, as [lng, lat] pairs. */
export interface ExploreLine {
	id: string;
	coords: [number, number][];
}

export interface LatLng {
	lat: number;
	lng: number;
}

export interface ViewBounds {
	west: number;
	south: number;
	east: number;
	north: number;
}

export type ExploreSort = 'nearest' | 'most_run' | 'name';

export type DistanceBucket = 'any' | 'short' | 'medium' | 'long' | 'ultra';

export interface ViewportFilter {
	distance: DistanceBucket;
	unit: 'km' | 'mi';
	/** null for any surface. */
	surface: string | null;
	featuredOnly: boolean;
}

export const ANY_FILTER: Omit<ViewportFilter, 'unit'> = {
	distance: 'any',
	surface: null,
	featuredOnly: false,
};

const METRES_PER_MILE = 1609.344;

/**
 * A bucket's bounds in metres, min inclusive and max exclusive. The ladder is
 * the race ladder of the reader's unit: 5 / 10 / 21 km, or 3 / 6 / 13 mi.
 */
export function distanceBucketBounds(
	bucket: DistanceBucket,
	unit: 'km' | 'mi',
): { min: number | null; max: number | null } {
	const [a, b, c] =
		unit === 'mi' ? [3 * METRES_PER_MILE, 6 * METRES_PER_MILE, 13 * METRES_PER_MILE] : [5000, 10000, 21000];
	switch (bucket) {
		case 'any':
			return { min: null, max: null };
		case 'short':
			return { min: null, max: a };
		case 'medium':
			return { min: a, max: b };
		case 'long':
			return { min: b, max: c };
		case 'ultra':
			return { min: c, max: null };
	}
}

export function filterActive(f: Omit<ViewportFilter, 'unit'>): boolean {
	return f.distance !== 'any' || f.surface !== null || f.featuredOnly;
}

export function filterViewport<T extends ExplorePin>(pins: readonly T[], f: ViewportFilter): T[] {
	const { min, max } = distanceBucketBounds(f.distance, f.unit);
	return pins.filter(
		(p) =>
			(min === null || p.distanceM >= min) &&
			(max === null || p.distanceM < max) &&
			(f.surface === null || p.surface === f.surface) &&
			(!f.featuredOnly || p.featured),
	);
}

/** Nearest first only means something once the reader's place is known. */
export function defaultSort(origin: LatLng | null): ExploreSort {
	return origin ? 'nearest' : 'most_run';
}

/**
 * The list page's order. Every branch ends on the folded name and then the
 * id, so the order never depends on sort stability. Nearest with no origin
 * falls back to most run.
 */
export function sortViewport<T extends ExplorePin>(
	pins: readonly T[],
	sort: ExploreSort,
	origin: LatLng | null,
): T[] {
	const byName = (a: T, b: T) => compareFoldedNames(a.name, a.id, b.name, b.id);
	const out = [...pins];
	if (sort === 'nearest' && origin) {
		const d = new Map(out.map((p) => [p.id, haversineMetres(origin.lat, origin.lng, p.lat, p.lng)]));
		out.sort((a, b) => d.get(a.id)! - d.get(b.id)! || byName(a, b));
	} else if (sort === 'name') {
		out.sort(byName);
	} else {
		out.sort((a, b) => b.runCount - a.runCount || byName(a, b));
	}
	return out;
}

/** Whether a point is in view, across the antimeridian too. */
export function inBounds(lat: number, lng: number, b: ViewBounds): boolean {
	if (lat < b.south || lat > b.north) return false;
	return b.west <= b.east ? lng >= b.west && lng <= b.east : lng >= b.west || lng <= b.east;
}

/** The pin closest to [center], for the empty view's way back. */
export function nearestTo<T extends ExplorePin>(pins: readonly T[], center: LatLng): T | null {
	let best: T | null = null;
	let bestD = Infinity;
	for (const p of pins) {
		const d = haversineMetres(center.lat, center.lng, p.lat, p.lng);
		if (d < bestD || (d === bestD && best !== null && compareFoldedNames(p.name, p.id, best.name, best.id) < 0)) {
			best = p;
			bestD = d;
		}
	}
	return best;
}
