import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { countInView, parkMarkerPoint, pointInView, type LatLng, type MapBounds } from './park_map';

// The TS reader of fixtures/park_map_cases.json, the case table the Dart twin
// (apps/mobile_android/test/park_map_test.dart) reads too.
const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..', '..', '..');
type Pt = { lat: number | null; lng: number | null };
const { markerCases, viewCases } = JSON.parse(readFileSync(join(REPO, 'fixtures', 'park_map_cases.json'), 'utf-8')) as {
	markerCases: { name: string; centroid: Pt | null; lines: Pt[][]; point: LatLng | null }[];
	viewCases: { name: string; bounds: MapBounds; points: (LatLng | null)[]; inView: boolean[] }[];
};

for (const c of markerCases) {
	test(`marker: ${c.name}`, () => {
		const got = parkMarkerPoint(c.centroid, c.lines);
		if (c.point === null) {
			assert.equal(got, null);
			return;
		}
		assert.ok(got);
		assert.ok(Math.abs(got.lat - c.point.lat) < 1e-9, `lat ${got.lat}`);
		assert.ok(Math.abs(got.lng - c.point.lng) < 1e-9, `lng ${got.lng}`);
	});
}

for (const c of viewCases) {
	test(`view: ${c.name}`, () => {
		assert.deepEqual(
			c.points.map((p) => pointInView(p, c.bounds)),
			c.inView,
		);
		assert.equal(countInView(c.points, c.bounds), c.inView.filter(Boolean).length);
	});
}
