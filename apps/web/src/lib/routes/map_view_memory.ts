/// Where a browse map opens (decisions § 2613): on the best place it knows,
/// moving to a better one as it arrives, until the reader moves the map. The
/// web knows three, weakest first: the world, where the reader last left this
/// map (kept in this browser), and where they are, read only when they have
/// already granted location so opening the map never prompts. Mobile adds the
/// start of the runner's newest run between the world and the remembered view.

import { localStore } from '#lib/core/browser_storage.ts';

export interface MapView {
	lat: number;
	lng: number;
	zoom: number;
}

export type MapOpening = 'world' | 'remembered' | 'here';

const RANK: Record<MapOpening, number> = { world: 0, remembered: 1, here: 2 };

/// Whether a map that opened on `current` moves to `next`: only to a stronger
/// opening, and never once the reader has moved it themselves.
export function opensOn(current: MapOpening, next: MapOpening, touched: boolean): boolean {
	return !touched && RANK[next] > RANK[current];
}

/// The least zoom worth remembering: the world view a map opens on when it
/// knows nothing is not a place the reader chose.
export const REMEMBERED_MIN_ZOOM = 4;

export const EXPLORE_ROUTES_VIEW_KEY = 'explore_routes_last_view';

export function encodeMapView(v: MapView): string {
	return `${v.lat},${v.lng},${v.zoom}`;
}

/// Null for anything that is not three finite numbers with the centre on the
/// globe, so a corrupt value opens the map on a weaker view.
export function decodeMapView(raw: string): MapView | null {
	const parts = raw.split(',');
	if (parts.length !== 3) return null;
	const [lat, lng, zoom] = parts.map((p) => (p.trim() === '' ? Number.NaN : Number(p)));
	if (![lat, lng, zoom].every(Number.isFinite)) return null;
	if (Math.abs(lat) > 90 || Math.abs(lng) > 180) return null;
	return { lat, lng, zoom };
}

export function loadMapView(key: string, store: Storage | null = localStore()): MapView | null {
	try {
		const raw = store?.getItem(key);
		return raw ? decodeMapView(raw) : null;
	} catch {
		return null;
	}
}

export function saveMapView(key: string, view: MapView, store: Storage | null = localStore()): void {
	if (view.zoom < REMEMBERED_MIN_ZOOM) return;
	try {
		store?.setItem(key, encodeMapView(view));
	} catch {
		// Quota or private mode: the map opens on a weaker view next time.
	}
}

/// Where the reader is, only when the browser already holds a location grant:
/// opening a map must never raise the permission prompt (Near me asks). Null
/// when the grant is missing, the Permissions API is absent, or no fix comes
/// within `timeoutMs`.
export async function quietFix(
	nav: Pick<Navigator, 'geolocation' | 'permissions'> | undefined = typeof navigator === 'undefined'
		? undefined
		: navigator,
	timeoutMs = 8000,
): Promise<{ lat: number; lng: number } | null> {
	if (!nav?.geolocation || !nav.permissions?.query) return null;
	try {
		const status = await nav.permissions.query({ name: 'geolocation' });
		if (status.state !== 'granted') return null;
	} catch {
		return null;
	}
	return new Promise((resolve) => {
		nav.geolocation.getCurrentPosition(
			(pos) => resolve({ lat: pos.coords.latitude, lng: pos.coords.longitude }),
			() => resolve(null),
			{ enableHighAccuracy: false, maximumAge: 10 * 60 * 1000, timeout: timeoutMs },
		);
	});
}
