import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * Park courses are map-first at phone width (decisions § 2612): the index is
 * a map of parks with a "List · N parks" button whose list is its own view
 * (back returns to the map), and a park page opens on its map, with roomy
 * course cards under it; a card previews its course in a floating card with
 * See the route and Board, and the notices sit in About this park.
 *
 * Planted (service role) in one park under a unique slug at (36.4, -79.6),
 * which no seed row or other spec uses, and removed afterwards. Two more
 * parks, a few hundred metres apart under a tag of their own at (36.2, -79.9),
 * stand for a crowd whose pills would overlap.
 */

const M_PER_DEG_LAT = 111_320;
const LAT = 36.4;
const LNG = -79.6;
const TAG = `${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;
const PARK_SLUG = `e2e-mapfirst-park-${TAG}`;
const PARK_NAME = `E2E Map First State Park ${TAG}`;
const PARK_PATH = `/parks/us-va/${PARK_SLUG}`;
const LONG_NAME = `The Very Long Lakeside And Ridge Connector Loop Through The Old Hardwood Forest ${TAG}`;

const PAIR = `pair${Math.random().toString(36).slice(2, 8)}`;
const PAIR_NAMES = [`E2E Crowded North Park ${PAIR}`, `E2E Crowded South Park ${PAIR}`];

let parkId: string | null = null;
const pairIds: string[] = [];
const segmentIds: string[] = [];

test.beforeAll(async () => {
	const admin = getAdminClient();
	const park = await admin
		.from('parks')
		.insert({
			slug: PARK_SLUG,
			name: PARK_NAME,
			description: 'A lake park in the piedmont.',
			website_url: 'https://example.org/park',
			agency: 'state',
			region_code: 'US-VA',
			country_code: 'US',
			timezone: 'America/New_York',
		})
		.select('id')
		.single();
	if (park.error) throw park.error;
	parkId = park.data.id;
	for (const [i, c] of [
		{ slug: 'long', name: LONG_NAME, distanceM: 6_400 },
		{ slug: 'short', name: `Short Loop ${TAG}`, distanceM: 2_000 },
	].entries()) {
		const lng = LNG + i * 0.01;
		const seg = await admin
			.from('global_segments')
			.insert({
				name: c.name,
				waypoints: [
					{ lat: LAT, lng },
					{ lat: LAT + 800 / M_PER_DEG_LAT, lng },
					{ lat: LAT + 800 / M_PER_DEG_LAT, lng: lng + 0.005 },
					{ lat: LAT, lng },
				],
				distance_m: c.distanceM,
				elevation_m: 40,
				surface: 'trail',
				country_code: 'US',
			})
			.select('id')
			.single();
		if (seg.error) throw seg.error;
		segmentIds.push(seg.data.id);
		const course = await admin.from('park_courses').insert({
			park_id: parkId,
			global_segment_id: seg.data.id,
			slug: c.slug,
			course_shape: 'loop',
			geometry_source: 'osm',
			checkpoints: [],
		});
		if (course.error) throw course.error;
	}
	for (const [i, name] of PAIR_NAMES.entries()) {
		const pair = await admin
			.from('parks')
			.insert({
				slug: `e2e-crowded-${i}-${PAIR}`,
				name,
				agency: 'state',
				region_code: 'US-VA',
				country_code: 'US',
				timezone: 'America/New_York',
				centroid_lat: 36.2 - i * 0.004,
				centroid_lng: -79.9 - i * 0.004,
			})
			.select('id')
			.single();
		if (pair.error) throw pair.error;
		pairIds.push(pair.data.id);
	}
});

test.afterAll(async () => {
	const admin = getAdminClient();
	if (parkId) await admin.from('parks').delete().eq('id', parkId);
	if (pairIds.length) await admin.from('parks').delete().in('id', pairIds);
	if (segmentIds.length) await admin.from('global_segments').delete().in('id', segmentIds);
});

test.describe('park courses on a phone', () => {
	test.use({ storageState: USER_A.storageStatePath, viewport: { width: 390, height: 844 } });

	test('the index is a map; List opens the parks as a list and back returns to the map', async ({ page }) => {
		await page.goto('/parks');
		const list = page.getByTestId('parks-list-button');
		await expect(list).toBeVisible({ timeout: 15_000 });
		await expect(list).toHaveText(/List · \d+ parks?/);
		await expect(page.getByTestId('parks-search')).toBeVisible();
		await expect(page.getByTestId('parks-list')).toBeHidden();
		// The intro is one tap away, behind How park courses work.
		await expect(page.getByText('Standing time-trial courses')).toHaveCount(0);

		await list.click();
		await expect(page).toHaveURL(/\/parks\?view=list$/);
		await expect(page.getByTestId('parks-list')).toBeVisible();
		await expect(page.getByTestId('parks-list-button')).toBeHidden();

		await page.goBack();
		await expect(page).toHaveURL(/\/parks$/);
		await expect(page.getByTestId('parks-list-button')).toBeVisible();
		await expect(page.getByTestId('parks-list')).toBeHidden();

		await page.getByTestId('parks-list-button').click();
		await page.getByTestId('parks-map-button').click();
		await expect(page).toHaveURL(/\/parks$/);
		await expect(page.getByTestId('parks-list-button')).toBeVisible();
	});

	test("a park's pin names it with its course count and opens it", async ({ page }) => {
		await page.goto(`/parks?q=${encodeURIComponent(TAG)}`);
		// The signed-in reader accepted the cookie notice, so the map draws at once.
		await expect(page.getByTestId('parks-map-consent')).toHaveCount(0);
		await expect(page.getByTestId('parks-near-me')).toBeVisible();
		const pin = page.getByTestId('parks-map-pin').filter({ hasText: PARK_NAME });
		await expect(pin).toHaveCount(1, { timeout: 15_000 });
		await expect(pin).toHaveAccessibleName(`${PARK_NAME}, 2 courses`);
		await expect(page.getByTestId('parks-list-button')).toHaveText(/List · 1 park$/);
		await pin.click();
		await page.waitForURL(`**${PARK_PATH}`);
	});

	test('parks whose pills would overlap share one "2 parks" button that zooms in until each has its own', async ({
		page,
	}) => {
		await page.goto(`/parks?q=${PAIR}`);
		const group = page.getByTestId('parks-map-group');
		await expect(group).toHaveCount(1, { timeout: 15_000 });
		await expect(group).toHaveText('2 parks');
		await expect(group).toHaveAccessibleName('2 parks here. Zoom in to see them');
		await expect(page.getByTestId('parks-map-pin')).toHaveCount(0);
		await expect(page.getByTestId('parks-list-button')).toHaveText(/List · 2 parks$/);
		await group.click();
		for (const name of PAIR_NAMES) {
			await expect(page.getByTestId('parks-map-pin').filter({ hasText: name })).toHaveCount(1, { timeout: 15_000 });
		}
		await expect(page.getByTestId('parks-map-group')).toHaveCount(0);
	});

	test('a search finds the park in the list view and its card opens it', async ({ page }) => {
		await page.goto('/parks?view=list');
		await page.getByTestId('parks-search').fill(TAG);
		const card = page.getByTestId('park-card').filter({ hasText: PARK_NAME });
		await expect(card).toHaveCount(1, { timeout: 15_000 });
		await card.click();
		await page.waitForURL(`**${PARK_PATH}`);
		await expect(page.getByRole('heading', { level: 1, name: PARK_NAME })).toBeVisible();
	});

	test('a park opens on its map, and a card previews its course with Board', async ({ page }) => {
		await page.goto(PARK_PATH);
		await expect(page.getByRole('heading', { level: 1 })).toHaveCount(1, { timeout: 15_000 });
		const map = page.getByTestId('park-overview-map');
		const firstCard = page.getByTestId('park-course-card').first();
		await expect(firstCard).toBeVisible();
		const mapBox = await map.boundingBox();
		const cardBox = await firstCard.boundingBox();
		expect(mapBox && cardBox && mapBox.y < cardBox.y, 'the map comes before the courses').toBe(true);
		expect(mapBox!.height, 'the map takes a good share of the screen').toBeGreaterThan(844 * 0.3);

		// The whole long name reads on its card, never cut.
		const longCard = page.getByTestId('park-course-card').filter({ hasText: 'Connector Loop' });
		const title = longCard.locator('.list-card-title');
		await expect(title).toHaveText(LONG_NAME);
		const fits = await title.evaluate((el) => el.scrollHeight <= el.clientHeight + 1 && el.scrollWidth <= el.clientWidth + 1);
		expect(fits, 'the name is not clipped').toBe(true);
		await expect(longCard.getByTestId('park-course-distance')).toContainText('6.4 km');

		await longCard.locator('button.lc-tap').click();
		const preview = page.getByTestId('park-course-preview');
		await expect(preview).toBeVisible();
		await expect(preview.getByRole('heading', { level: 2 })).toHaveText(LONG_NAME);
		const board = preview.getByTestId('park-course-preview-open');
		await expect(board).toHaveAccessibleName('Board');
		// No official route planted, so there is nothing to see on /routes.
		await expect(preview.getByTestId('park-course-preview-route')).toHaveCount(0);
		await expect(page.getByTestId('park-map-start-here')).toBeVisible();

		await preview.getByTestId('park-course-preview-close').click();
		await expect(preview).toHaveCount(0);

		await longCard.locator('button.lc-tap').click();
		await page.getByTestId('park-course-preview').getByTestId('park-course-preview-open').click();
		await page.waitForURL(`**${PARK_PATH}/long`);
	});

	test('About this park holds the description, the website and the notices', async ({ page }) => {
		await page.goto(PARK_PATH);
		const about = page.getByTestId('park-about');
		await expect(about).toBeVisible({ timeout: 15_000 });
		await expect(page.getByTestId('park-not-affiliated')).toBeHidden();
		await page.getByTestId('park-about-toggle').click();
		await expect(about.getByText('A lake park in the piedmont.')).toBeVisible();
		await expect(page.getByTestId('park-website')).toHaveAccessibleName('Website');
		await expect(page.getByTestId('park-not-affiliated')).toBeVisible();
		await expect(page.getByTestId('park-group-permit')).toContainText('may need a permit from the park');
	});

	test('nothing scrolls sideways at 320 px', async ({ page }) => {
		await page.setViewportSize({ width: 320, height: 640 });
		for (const path of ['/parks', '/parks?view=list', PARK_PATH]) {
			await page.goto(path);
			await expect(page.getByTestId('park-back').or(page.getByTestId('parks-back-to-races'))).toBeVisible({ timeout: 15_000 });
			const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
			expect(overflow, `${path} scrolls sideways`).toBeLessThanOrEqual(0);
		}
	});
});
