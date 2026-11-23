// Parks on a map: where each park's marker sits and which markers a map view
// holds, for the parks index's "List · N parks". Pure.
//
// Parity pair with apps/mobile_android/lib/park_map.dart. Both read
// fixtures/park_map_cases.json.

export interface LatLng {
	lat: number;
	lng: number;
}

export interface MapBounds {
	south: number;
	west: number;
	north: number;
	east: number;
}

function usable(lat: number | null | undefined, lng: number | null | undefined): lat is number {
	return (
		typeof lat === 'number' &&
		typeof lng === 'number' &&
		Number.isFinite(lat) &&
		Number.isFinite(lng) &&
		Math.abs(lat) <= 90 &&
		Math.abs(lng) <= 180
	);
}

/**
 * Where a park's marker goes: its stored centroid, else the middle of the box
 * round every course line (most catalogue parks carry no centroid), else
 * nowhere.
 */
export function parkMarkerPoint(
	centroid: { lat: number | null | undefined; lng: number | null | undefined } | null | undefined,
	lines: readonly (readonly { lat: number | null | undefined; lng: number | null | undefined }[])[],
): LatLng | null {
	if (centroid && usable(centroid.lat, centroid.lng)) {
		return { lat: centroid.lat, lng: centroid.lng as number };
	}
	let south = Infinity;
	let north = -Infinity;
	let west = Infinity;
	let east = -Infinity;
	for (const line of lines) {
		for (const p of line) {
			if (!usable(p.lat, p.lng)) continue;
			const lng = p.lng as number;
			south = Math.min(south, p.lat);
			north = Math.max(north, p.lat);
			west = Math.min(west, lng);
			east = Math.max(east, lng);
		}
	}
	if (south === Infinity) return null;
	return { lat: (south + north) / 2, lng: (west + east) / 2 };
}

/** Whether a marker is inside a map view, edges included; a view whose west is
 *  east of its east crosses the antimeridian. */
export function pointInView(point: LatLng | null | undefined, view: MapBounds): boolean {
	if (!point) return false;
	if (point.lat < view.south || point.lat > view.north) return false;
	return view.west <= view.east
		? point.lng >= view.west && point.lng <= view.east
		: point.lng >= view.west || point.lng <= view.east;
}

/** How many of the markers a map view holds. */
export function countInView(points: readonly (LatLng | null | undefined)[], view: MapBounds): number {
	let n = 0;
	for (const p of points) if (pointInView(p, view)) n++;
	return n;
}
