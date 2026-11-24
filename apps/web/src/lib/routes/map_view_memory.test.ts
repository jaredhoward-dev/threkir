import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
	decodeMapView,
	encodeMapView,
	loadMapView,
	opensOn,
	quietFix,
	saveMapView,
} from './map_view_memory.ts';

function memoryStore(seed: Record<string, string> = {}): Storage {
	const data = new Map(Object.entries(seed));
	return {
		get length() {
			return data.size;
		},
		clear: () => data.clear(),
		getItem: (k) => data.get(k) ?? null,
		key: (i) => [...data.keys()][i] ?? null,
		removeItem: (k) => void data.delete(k),
		setItem: (k, v) => void data.set(k, String(v)),
	};
}

test('decodeMapView round-trips what encodeMapView writes', () => {
	const view = { lat: 37.5407, lng: -77.436, zoom: 12.5 };
	assert.deepEqual(decodeMapView(encodeMapView(view)), view);
});

test('decodeMapView refuses anything that is not three finite numbers on the globe', () => {
	for (const raw of ['', '1,2', '1,2,3,4', 'a,2,3', '1,,3', 'NaN,2,3', '1,Infinity,3', '91,0,5', '0,181,5']) {
		assert.equal(decodeMapView(raw), null, raw);
	}
});

test('a map moves only to a stronger opening, and never once touched', () => {
	assert.equal(opensOn('world', 'remembered', false), true);
	assert.equal(opensOn('remembered', 'here', false), true);
	assert.equal(opensOn('here', 'remembered', false), false);
	assert.equal(opensOn('remembered', 'remembered', false), false);
	assert.equal(opensOn('world', 'here', true), false);
});

test('a chosen view is remembered; the world view and a corrupt value are not', () => {
	const store = memoryStore();
	assert.equal(loadMapView('k', store), null);
	saveMapView('k', { lat: 37.5, lng: -77.4, zoom: 12 }, store);
	assert.deepEqual(loadMapView('k', store), { lat: 37.5, lng: -77.4, zoom: 12 });
	saveMapView('k', { lat: 20, lng: 0, zoom: 2 }, store);
	assert.deepEqual(loadMapView('k', store), { lat: 37.5, lng: -77.4, zoom: 12 });
	assert.equal(loadMapView('k', memoryStore({ k: 'not a view' })), null);
});

test('no storage, or storage that throws, opens on a weaker view', () => {
	assert.equal(loadMapView('k', null), null);
	const throwing = { ...memoryStore(), getItem: () => { throw new Error('blocked'); }, setItem: () => { throw new Error('quota'); } };
	assert.equal(loadMapView('k', throwing), null);
	assert.doesNotThrow(() => saveMapView('k', { lat: 1, lng: 2, zoom: 10 }, throwing));
});

function fakeNav(state: PermissionState, fix: { lat: number; lng: number } | null) {
	let asked = 0;
	const nav = {
		permissions: { query: async () => ({ state }) as PermissionStatus } as unknown as Permissions,
		geolocation: {
			getCurrentPosition: (ok: PositionCallback, fail?: PositionErrorCallback | null) => {
				asked++;
				if (fix) ok({ coords: { latitude: fix.lat, longitude: fix.lng } } as GeolocationPosition);
				else fail?.({ code: 3 } as GeolocationPositionError);
			},
		} as unknown as Geolocation,
	};
	return { nav, asked: () => asked };
}

test('quietFix reads a position only when location is already granted', async () => {
	const granted = fakeNav('granted', { lat: 40.7, lng: -74 });
	assert.deepEqual(await quietFix(granted.nav), { lat: 40.7, lng: -74 });

	for (const state of ['prompt', 'denied'] as const) {
		const f = fakeNav(state, { lat: 1, lng: 2 });
		assert.equal(await quietFix(f.nav), null, state);
		assert.equal(f.asked(), 0, `${state}: never asks the browser, which would prompt`);
	}
});

test('quietFix is null with no fix, no Permissions API, or no navigator', async () => {
	assert.equal(await quietFix(fakeNav('granted', null).nav), null);
	const noPermissions = { geolocation: fakeNav('granted', { lat: 1, lng: 2 }).nav.geolocation } as Pick<
		Navigator,
		'geolocation' | 'permissions'
	>;
	assert.equal(await quietFix(noPermissions), null);
	assert.equal(await quietFix(undefined), null);
});
