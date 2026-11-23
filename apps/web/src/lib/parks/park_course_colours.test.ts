import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { PARK_COURSE_LINE_COLOURS, parkCourseLineColour } from './park_course_colours';

const SRC = join(dirname(fileURLToPath(import.meta.url)), '..', '..');

// app.css declares the light marks once and the dark ones under the
// prefers-color-scheme block and again under [data-theme="dark"].
function kindBlocks(): string[][] {
	const css = readFileSync(join(SRC, 'app.css'), 'utf-8');
	const all = [...css.matchAll(/--kind-([1-6]):\s*(#[0-9A-Fa-f]{6});/g)].map((m) => m[2].toUpperCase());
	const blocks: string[][] = [];
	for (let i = 0; i < all.length; i += 6) blocks.push(all.slice(i, i + 6));
	return blocks;
}

test('the light lines are the light --kind marks', () => {
	assert.deepEqual([...PARK_COURSE_LINE_COLOURS.light].map((c) => c.toUpperCase()), kindBlocks()[0]);
});

test('the dark lines are the dark --kind marks, in both dark blocks', () => {
	const blocks = kindBlocks();
	assert.ok(blocks.length >= 3);
	for (const b of blocks.slice(1)) {
		assert.deepEqual([...PARK_COURSE_LINE_COLOURS.dark].map((c) => c.toUpperCase()), b);
	}
});

test('a seventh course takes the first colour again', () => {
	assert.equal(parkCourseLineColour(6, false), PARK_COURSE_LINE_COLOURS.light[0]);
	assert.equal(parkCourseLineColour(1, true), PARK_COURSE_LINE_COLOURS.dark[1]);
});
