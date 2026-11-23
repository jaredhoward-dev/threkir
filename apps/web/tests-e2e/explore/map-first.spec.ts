import type { Page } from '@playwright/test';

import { expect, test } from '../fixtures/test';
import { USER_A } from '../fixtures/users';
import { acceptCookieConsent } from '../fixtures/helpers';

/**
 * Routes → Explore at phone width is map first (decisions § 2611): a tapped
 * pin opens a card with the whole name and the Official line off the title,
 * "List · N routes" opens the routes in view as a page of their own, a card
 * there returns to the map with that route selected, and browser back from
 * the list returns to the map.
 *
 * The routes in view and the selected line are stubbed, so the flow does not
 * depend on what the seed happens to have near the camera.
 */

const START: [number, number] = [-104.99, 39.74];
const LONG_NAME = 'Cherry Creek Trail out-and-back to Confluence Park and the long way home';

const PINS = [
	{
		id: '00000000-0000-4000-8000-00000000e001',
		name: LONG_NAME,
		slug: null,
		is_featured: false,
		distance_m: 12500,
		elevation_m: 80,
		surface: 'trail',
		run_count: 9,
		lng: START[0],
		lat: START[1],
		is_official: true,
	},
	{
		id: '00000000-0000-4000-8000-00000000e002',
		name: 'Wash Park Loop',
		slug: null,
		is_featured: false,
		distance_m: 4200,
		elevation_m: 12,
		surface: 'road',
		run_count: 2,
		lng: START[0] + 0.02,
		lat: START[1] - 0.012,
		is_official: false,
	},
];

type ExploreHooks = {
	__exploreMap?: {
		jumpTo: (o: { center: [number, number]; zoom: number }) => void;
		project: (lngLat: [number, number]) => { x: number; y: number };
		getContainer: () => HTMLElement;
		loaded: () => boolean;
		isMoving: () => boolean;
	};
	__explorePinsSettled?: () => boolean;
};

async function settled(page: Page) {
	await page.waitForFunction(
		() => {
			const w = window as unknown as ExploreHooks;
			const m = w.__exploreMap;
			return !!m && !!w.__explorePinsSettled?.() && m.loaded() && !m.isMoving();
		},
		undefined,
		{ timeout: 15_000 },
	);
}

/** The viewport pixel of a lng/lat on the settled camera. */
async function pixelOf(page: Page, at: [number, number]) {
	return page.evaluate(([lng, lat]) => {
		const m = (window as unknown as ExploreHooks).__exploreMap!;
		const pt = m.project([lng, lat]);
		const rect = m.getContainer().getBoundingClientRect();
		return { x: rect.left + pt.x, y: rect.top + pt.y };
	}, at);
}

test.describe('/routes?tab=explore — map first at phone width', () => {
	test.use({ storageState: USER_A.storageStatePath, viewport: { width: 390, height: 844 } });

	test.beforeEach(async ({ context }) => {
		await acceptCookieConsent(context);
	});

	test('tap a pin for its card, open the list, pick a route, and back returns to the map', async ({
		page,
		mockRoute,
	}) => {
		await mockRoute(page, '**/rest/v1/rpc/discoverable_routes_in_bbox', (route) =>
			route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(PINS) }),
		);
		await mockRoute(page, /\/rest\/v1\/rpc\/clip_route_for_viewer/, (route) =>
			route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify([
					{ lat: START[1], lng: START[0] },
					{ lat: START[1] + 0.01, lng: START[0] + 0.01 },
				]),
			}),
		);

		await page.goto('/routes?tab=explore');
		await expect(page.getByTestId('routes-view-menu-button')).toContainText('Explore routes', { timeout: 15_000 });
		await settled(page);
		await page.evaluate((center) => {
			(window as unknown as ExploreHooks).__exploreMap!.jumpTo({ center, zoom: 13 });
		}, START);
		await settled(page);

		await expect(page.getByTestId('explore-list-pill')).toHaveText(/List · 2 routes/);

		const pin = await pixelOf(page, START);
		await page.mouse.click(pin.x, pin.y);
		const card = page.getByTestId('explore-route-card');
		await expect(card).toBeVisible();
		await expect(card.getByRole('heading', { name: LONG_NAME })).toBeVisible();
		await expect(card.getByTestId('explore-card-official')).toHaveText(/Official course/);
		await expect(card.getByRole('link', { name: 'See the route' })).toHaveAttribute(
			'href',
			`/routes/${PINS[0].id}?from=explore`,
		);

		await card.getByTestId('explore-card-close').click();
		await expect(card).toHaveCount(0);

		await page.getByTestId('explore-list-pill').click();
		await expect(page).toHaveURL(/view=list/);
		await expect(page.getByRole('heading', { name: 'Routes on the map' })).toBeVisible();
		const rows = page.getByTestId('explore-list-card');
		await expect(rows).toHaveCount(2);
		await expect(rows.first()).toContainText(LONG_NAME);

		await rows.filter({ hasText: 'Wash Park Loop' }).click();
		await expect(page).not.toHaveURL(/view=list/);
		await expect(page.getByTestId('explore-route-card').getByRole('heading', { name: 'Wash Park Loop' })).toBeVisible();

		await page.getByTestId('explore-route-card').getByTestId('explore-card-close').click();
		await page.getByTestId('explore-list-pill').click();
		await expect(page).toHaveURL(/view=list/);
		await page.goBack();
		await expect(page).not.toHaveURL(/view=list/);
		await expect(page.getByTestId('explore-list-pill')).toBeVisible();
	});

	test('the view menu switches between My routes, Explore routes and Explore segments', async ({ page }) => {
		await page.goto('/routes?tab=explore');
		await page.getByTestId('routes-view-menu-button').click();
		await expect(page.getByTestId('routes-view-menu-routes')).toHaveAttribute('aria-current', 'page');
		await page.getByTestId('routes-view-menu-segments').click();
		await expect(page).toHaveURL(/\/segments$/);
		await expect(page.getByTestId('routes-view-menu-button')).toContainText('Explore segments', { timeout: 15_000 });
		await page.getByTestId('routes-view-menu-button').click();
		await page.getByTestId('routes-view-menu-mine').click();
		await expect(page).toHaveURL(/\/routes$/);
		await expect(page.getByTestId('routes-view-menu-button')).toContainText('My routes');
	});

	test('an empty view says so and offers to zoom out', async ({ page, mockRoute }) => {
		await mockRoute(page, '**/rest/v1/rpc/discoverable_routes_in_bbox', (route) =>
			route.fulfill({ status: 200, contentType: 'application/json', body: '[]' }),
		);
		await page.goto('/routes?tab=explore');
		await settled(page);
		const empty = page.getByTestId('explore-empty-view');
		await expect(empty).toContainText('No routes here');
		await expect(empty.getByTestId('explore-zoom-out')).toBeVisible();
		await expect(page.getByTestId('explore-list-pill')).toHaveText(/List · 0 routes/);
	});
});
