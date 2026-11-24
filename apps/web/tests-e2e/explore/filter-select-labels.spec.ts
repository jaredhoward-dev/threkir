import { expect, test } from '../fixtures/test';

import { USER_A } from '../fixtures/users';

/**
 * Accessible-name pins for Explore's filter and sort selects (UX-hunt web #4):
 * an unnamed `<select>` is announced as a bare combobox. Distance and surface
 * live in the Filters sheet the map's Filters button opens, and the sort in
 * the list beside the map (decisions § 2611); each is named by its label.
 */
test.describe('RouteExplorer filter selects have accessible names', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('distance, surface, and sort each expose an accessible name', async ({ page }) => {
		await page.goto('/routes?tab=explore');
		await expect(page.getByRole('combobox', { name: 'Sort' })).toBeVisible({ timeout: 10_000 });

		await page.getByTestId('explore-filters-open').click();
		const sheet = page.getByTestId('explore-filters');
		await expect(sheet.getByRole('combobox', { name: 'Filter by distance' })).toBeVisible();
		await expect(sheet.getByRole('combobox', { name: 'Filter by surface' })).toBeVisible();
	});

	test('no filter combobox is left without an accessible name', async ({ page }) => {
		await page.goto('/routes?tab=explore');
		await page.getByTestId('explore-filters-open').click();
		const sheet = page.getByTestId('explore-filters');
		await expect(sheet.getByRole('combobox')).toHaveCount(2);
		for (const box of await sheet.getByRole('combobox').all()) {
			await expect(box).toHaveAccessibleName(/.+/);
		}
	});
});
