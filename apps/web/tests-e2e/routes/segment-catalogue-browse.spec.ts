import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * Famous-segment catalogue BROWSE journey — the discovery half of the
 * catalogue shipped in decisions §233, which until now could only be reached
 * by already having run one of its segments.
 *
 *   1. A curator plants two catalogue segments sharing a unique token, in
 *      different regions and on different surfaces, with different lengths
 *      and one accented name.
 *   2. /segments lists both. Searching the shared token narrows the page to
 *      exactly those two, so the assertions below are independent of whatever
 *      else the seeded catalogue holds (and of a concurrently-running spec).
 *   3. The accent fold is exercised end-to-end: an ASCII query reaches the
 *      accented name.
 *   4. Sorting by longest reorders the pair; the region filter narrows to one.
 *   5. A query that matches nothing shows the filtered-empty copy, NOT the
 *      empty-catalogue copy — the two states are distinct on purpose.
 *   6. A card shows its segment on the map, whose Details opens
 *      /segments/[id]; its back-link returns to the catalogue rather than the
 *      dashboard.
 *
 * Teardown removes both catalogue rows.
 */

const M_PER_DEG_LAT = 111_320;

function line(baseLat: number, lng: number, lengthM: number) {
	return [
		{ lat: baseLat, lng },
		{ lat: baseLat + lengthM / M_PER_DEG_LAT, lng }
	];
}

test.describe('famous-segment catalogue browse', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('browse, search, filter, sort, then open a catalogue segment', async ({ page }) => {
		const admin = getAdminClient();
		const token = `e2ecat${Date.now().toString(36)}`;
		const shortName = `Côte du ${token}`;
		const longName = `Boulevard ${token}`;
		const shortRegion = `Chamonix ${token}, FR`;
		const longRegion = `Sydney ${token}, AU`;

		let shortId = '';
		let longId = '';

		try {
			await test.step('a curator plants two catalogue segments', async () => {
				const { data, error } = await admin
					.from('global_segments')
					.insert([
						{
							name: shortName,
							waypoints: line(-37.51, 144.51, 600),
							distance_m: 600,
							elevation_m: 90,
							surface: 'trail',
							region: shortRegion,
							country_code: 'FR'
						},
						{
							name: longName,
							waypoints: line(-37.52, 144.52, 3000),
							distance_m: 3000,
							elevation_m: 5,
							surface: 'road',
							region: longRegion,
							country_code: 'AU'
						}
					])
					.select('id, name');
				if (error) throw error;
				const rows = (data ?? []) as { id: string; name: string }[];
				shortId = rows.find((r) => r.name === shortName)!.id;
				longId = rows.find((r) => r.name === longName)!.id;
			});

			// Explore segments is map first (decisions § 2611): the list holds the
			// segments in the map's view (all of them until the map has framed),
			// and a card shows its segment on the map, whose card opens the page.
			const list = () => page.getByTestId('segment-catalogue-list');
			const cards = () => list().locator('[data-testid^="segment-card-"]');
			const order = () => cards().evaluateAll((els) => els.map((el) => el.getAttribute('data-testid')));

			await test.step('the browse page lists the catalogue', async () => {
				await page.goto('/segments');
				await expect(list()).toBeVisible({ timeout: 15_000 });
				await expect(page.getByTestId(`segment-card-${shortId}`)).toBeVisible();
				await expect(page.getByTestId(`segment-card-${longId}`)).toBeVisible();
			});

			await test.step('search narrows to the planted pair, newest count reported', async () => {
				await page.getByTestId('segment-catalogue-search').fill(token);
				await expect(cards()).toHaveCount(2);
				await expect(page.getByTestId('segment-catalogue-count')).toHaveText('2 segments');
			});

			await test.step('the query folds accents — an ASCII spelling reaches Côte', async () => {
				await page.getByTestId('segment-catalogue-search').fill(`Cote du ${token}`);
				await expect(cards()).toHaveCount(1);
				await expect(page.getByTestId(`segment-card-${shortId}`)).toBeVisible();
				await expect(page.getByTestId('segment-catalogue-count')).toHaveText('1 segment');
			});

			await test.step('longest-first reorders the pair', async () => {
				await page.getByTestId('segment-catalogue-search').fill(token);
				await page.getByTestId('segment-catalogue-sort').selectOption('longest');
				expect(await order()).toEqual([`segment-card-${longId}`, `segment-card-${shortId}`]);

				await page.getByTestId('segment-catalogue-sort').selectOption('shortest');
				expect(await order()).toEqual([`segment-card-${shortId}`, `segment-card-${longId}`]);
			});

			await test.step('the region filter narrows to one', async () => {
				// The region filter lives in the Filters sheet; its changes apply at
				// once, so the list behind it is already right.
				await page.getByTestId('segment-catalogue-filters-toggle').click();
				await page.getByTestId('segment-catalogue-region').selectOption(longRegion);
				await page.getByTestId('segment-catalogue-filters-done').click();
				await expect(page.getByTestId('segment-catalogue-filters-toggle')).toContainText('Filters, 1 on');
				await expect(cards()).toHaveCount(1);
				await expect(page.getByTestId(`segment-card-${longId}`)).toBeVisible();
			});

			await test.step('a filter that matches nothing is not reported as an empty catalogue', async () => {
				await page.getByTestId('segment-catalogue-search').fill(`${token}-no-such-segment`);
				await expect(page.getByTestId('segment-catalogue-no-matches')).toBeVisible();
				await expect(page.getByTestId('segment-catalogue-empty')).toHaveCount(0);
			});

			await test.step('clearing restores the full catalogue', async () => {
				await page.getByTestId('segment-catalogue-no-matches').getByRole('button', { name: 'Clear filters' }).click();
				await expect(page.getByTestId(`segment-card-${shortId}`)).toBeVisible();
				await expect(page.getByTestId(`segment-card-${longId}`)).toBeVisible();
			});

			await test.step('a card shows the segment on the map, and its Details opens the page', async () => {
				await page.getByTestId(`segment-card-${shortId}`).click();
				const card = page.getByTestId('explore-segment-card');
				await expect(card.getByRole('heading', { name: shortName })).toBeVisible();
				await card.getByTestId('explore-card-details').click();
				await page.waitForURL(`**/segments/${shortId}`);
				await expect(page.locator('h1', { hasText: shortName })).toBeVisible({ timeout: 10_000 });

				await page.locator('a.back-link').click();
				await page.waitForURL('**/segments');
				await expect(list()).toBeVisible({ timeout: 15_000 });
			});
		} finally {
			for (const id of [shortId, longId]) {
				if (!id) continue;
				try {
					await admin.from('global_segments').delete().eq('id', id);
				} catch {
					// Best-effort teardown: a failure here must not mask the assertion
					// that already failed above.
				}
			}
		}
	});
});
