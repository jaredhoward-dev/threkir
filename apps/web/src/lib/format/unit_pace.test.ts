import { test } from 'node:test';
import assert from 'node:assert/strict';
import { distanceIn, fmtKmIn, fmtPaceIn, formatPaceIn, formatPaceNoSuffixIn, formatSpeedIn } from './unit_pace';

test('run pace reads per km, or per mile from the exact mile', () => {
	assert.equal(formatPaceIn(1650, 5000, 'km'), '5:30 /km');
	// 330 s/km × 1.609344 = 531.08 s/mi
	assert.equal(formatPaceIn(1650, 5000, 'mi'), '8:51 /mi');
	assert.equal(formatPaceIn(1800, 5000, 'mi'), '9:39 /mi');
	assert.equal(formatPaceNoSuffixIn(1650, 5000, 'km'), '5:30');
	assert.equal(formatPaceNoSuffixIn(1650, 5000, 'mi'), '8:51');
});

test('a pair that cannot make a pace shows the placeholder, not 0:00 or Infinity', () => {
	for (const [s, m] of [
		[0, 5000],
		[1650, 0],
		[-1, 5000],
		[1650, -5],
		[Number.NaN, 5000],
		[1650, Number.POSITIVE_INFINITY],
	]) {
		assert.equal(formatPaceIn(s, m, 'km'), '--:--', `${s}/${m}`);
		assert.equal(formatPaceNoSuffixIn(s, m, 'mi'), '--:--', `${s}/${m}`);
		assert.equal(formatSpeedIn(s, m, 'km', 'en'), '--', `${s}/${m}`);
	}
});

test('speed reads km/h or mph to one decimal in the reader locale', () => {
	assert.equal(formatSpeedIn(3600, 10000, 'km', 'en'), '10.0 km/h');
	assert.equal(formatSpeedIn(3600, 10000, 'mi', 'en'), '6.2 mph');
	assert.equal(formatSpeedIn(3000, 10000, 'km', 'de'), '12,0 km/h');
	// A mile in exactly 8 minutes is 7.5 mph, not a rounding of an approximate factor.
	assert.equal(formatSpeedIn(480, 1609.344, 'mi', 'en'), '7.5 mph');
});

test('distance converts to the preferred unit without rounding', () => {
	assert.deepEqual(distanceIn(5000, 'km'), { value: 5, unit: 'km' });
	assert.deepEqual(distanceIn(1609.344, 'mi'), { value: 1, unit: 'mi' });
	assert.deepEqual(distanceIn(0, 'mi'), { value: 0, unit: 'mi' });
});

test('plan distance keeps a fixed digit count', () => {
	assert.equal(fmtKmIn(10000, 'km', 'en'), '10.0 km');
	assert.equal(fmtKmIn(10000, 'mi', 'en'), '6.2 mi');
	assert.equal(fmtKmIn(10000, 'mi', 'en', 2), '6.21 mi');
	assert.equal(fmtKmIn(5210, 'km', 'de'), '5,2 km');
	assert.equal(fmtKmIn(0, 'km', 'en'), '0.0 km');
	assert.equal(fmtKmIn(null, 'km', 'en'), '—');
	assert.equal(fmtKmIn(undefined, 'mi', 'en'), '—');
});

test('plan pace converts canonical s/km and refuses a non-pace', () => {
	assert.equal(fmtPaceIn(300, 'km'), '5:00/km');
	// 300 × 1.609344 = 482.8 s/mi
	assert.equal(fmtPaceIn(300, 'mi'), '8:03/mi');
	for (const bad of [null, undefined, 0, -30, Number.NaN, Number.POSITIVE_INFINITY]) {
		assert.equal(fmtPaceIn(bad, 'km'), '—', String(bad));
	}
});
