import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
	defaultSort,
	distanceBucketBounds,
	filterActive,
	filterViewport,
	inBounds,
	nearestTo,
	sortViewport,
	type ExplorePin,
} from './explore_viewport.ts';

function pin(id: string, name: string, over: Partial<ExplorePin> = {}): ExplorePin {
	return { id, name, lat: 0, lng: 0, distanceM: 5000, surface: 'road', featured: false, runCount: 0, ...over };
}

test('distance buckets follow the race ladder of the reader unit', () => {
	assert.deepEqual(distanceBucketBounds('any', 'km'), { min: null, max: null });
	assert.deepEqual(distanceBucketBounds('short', 'km'), { min: null, max: 5000 });
	assert.deepEqual(distanceBucketBounds('long', 'km'), { min: 10000, max: 21000 });
	assert.deepEqual(distanceBucketBounds('ultra', 'mi'), { min: 13 * 1609.344, max: null });
	assert.deepEqual(distanceBucketBounds('medium', 'mi'), { min: 3 * 1609.344, max: 6 * 1609.344 });
});

test('filterViewport narrows by distance, surface and featured, min inclusive and max exclusive', () => {
	const pins = [
		pin('a', 'A', { distanceM: 4999 }),
		pin('b', 'B', { distanceM: 5000, surface: 'trail' }),
		pin('c', 'C', { distanceM: 9999, featured: true }),
		pin('d', 'D', { distanceM: 10000 }),
	];
	const ids = (f: Parameters<typeof filterViewport>[1]) => filterViewport(pins, f).map((p) => p.id);
	assert.deepEqual(ids({ distance: 'medium', unit: 'km', surface: null, featuredOnly: false }), ['b', 'c']);
	assert.deepEqual(ids({ distance: 'any', unit: 'km', surface: 'trail', featuredOnly: false }), ['b']);
	assert.deepEqual(ids({ distance: 'any', unit: 'km', surface: null, featuredOnly: true }), ['c']);
	assert.deepEqual(ids({ distance: 'short', unit: 'km', surface: null, featuredOnly: false }), ['a']);
});

test('filterActive is false only for the default filter', () => {
	assert.equal(filterActive({ distance: 'any', surface: null, featuredOnly: false }), false);
	assert.equal(filterActive({ distance: 'long', surface: null, featuredOnly: false }), true);
	assert.equal(filterActive({ distance: 'any', surface: 'road', featuredOnly: false }), true);
	assert.equal(filterActive({ distance: 'any', surface: null, featuredOnly: true }), true);
});

test('defaultSort is nearest only once the reader place is known', () => {
	assert.equal(defaultSort(null), 'most_run');
	assert.equal(defaultSort({ lat: 1, lng: 2 }), 'nearest');
});

test('sortViewport nearest orders by distance from the origin, ties by folded name', () => {
	const pins = [
		pin('far', 'Far', { lat: 1, lng: 0 }),
		pin('z', 'Zed', { lat: 0.1, lng: 0 }),
		pin('e', 'Éa', { lat: 0.1, lng: 0 }),
	];
	assert.deepEqual(
		sortViewport(pins, 'nearest', { lat: 0, lng: 0 }).map((p) => p.id),
		['e', 'z', 'far'],
	);
});

test('sortViewport most run puts the busiest first, and nearest with no origin falls back to it', () => {
	const pins = [pin('a', 'B', { runCount: 2 }), pin('b', 'A', { runCount: 9 }), pin('c', 'A', { runCount: 2 })];
	assert.deepEqual(sortViewport(pins, 'most_run', null).map((p) => p.id), ['b', 'c', 'a']);
	assert.deepEqual(sortViewport(pins, 'nearest', null).map((p) => p.id), ['b', 'c', 'a']);
});

test('sortViewport name folds accents and breaks ties on id, leaving the input alone', () => {
	const pins = [pin('2', 'zurich'), pin('1', 'Zürich'), pin('3', 'Alpha')];
	assert.deepEqual(sortViewport(pins, 'name', null).map((p) => p.id), ['3', '1', '2']);
	assert.deepEqual(pins.map((p) => p.id), ['2', '1', '3']);
});

test('inBounds handles a view across the antimeridian', () => {
	const plain = { west: -10, south: -10, east: 10, north: 10 };
	assert.equal(inBounds(0, 0, plain), true);
	assert.equal(inBounds(11, 0, plain), false);
	assert.equal(inBounds(0, -11, plain), false);
	const wrapped = { west: 170, south: -10, east: -170, north: 10 };
	assert.equal(inBounds(0, 175, wrapped), true);
	assert.equal(inBounds(0, -175, wrapped), true);
	assert.equal(inBounds(0, 0, wrapped), false);
});

test('nearestTo picks the closest pin, and null with none', () => {
	assert.equal(nearestTo([], { lat: 0, lng: 0 }), null);
	const pins = [pin('far', 'Far', { lat: 5, lng: 5 }), pin('near', 'Near', { lat: 1, lng: 1 })];
	assert.equal(nearestTo(pins, { lat: 0, lng: 0 })?.id, 'near');
});
