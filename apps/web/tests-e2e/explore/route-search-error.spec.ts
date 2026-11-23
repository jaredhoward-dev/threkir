import { expect, test } from '../fixtures/test';

import { USER_A } from '../fixtures/users';
import { acceptCookieConsent } from '../fixtures/helpers';

/**
 * /routes?tab=explore — when the public-route search read fails, the search
 * panel says the read failed instead of "no routes match", which a reader
 * cannot tell from a real empty result (searchPublicRoutes used to swallow
 * the error to []).
 */

test.describe('/routes?tab=explore — search failure', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async ({ context }) => {
		await acceptCookieConsent(context);
	});

	test('a failed search says so, not that nothing matched', async ({ page, mockRoute }) => {
		// The search reads the public_routes view with an `order`; the other
		// public_routes reads on the page carry none, so only the search fails.
		await mockRoute(page, '**/rest/v1/public_routes*', async (route) => {
			if (!new URL(route.request().url()).searchParams.has('order')) {
				await route.fallback();
				return;
			}
			await route.fulfill({
				status: 500,
				contentType: 'application/json',
				body: JSON.stringify({ message: 'simulated search failure' })
			});
		});

		await page.goto('/routes?tab=explore');
		await page.getByTestId('explore-search-open').click();
		await page.getByTestId('explore-search').fill('park');

		const panel = page.getByTestId('explore-search-panel');
		await expect(panel.getByText("Couldn't load routes", { exact: true })).toBeVisible({ timeout: 10_000 });
		await expect(panel.getByText('No routes match your search')).toHaveCount(0);
	});
});
