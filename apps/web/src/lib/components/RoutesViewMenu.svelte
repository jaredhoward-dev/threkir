<script lang="ts">
	import { m } from '#lib/i18n/store.svelte.ts';

	// One button naming the view on screen, opening the three views: My routes,
	// Explore routes, Explore segments (decisions § 2611). At phone width it
	// stands in for the two rows of RoutesViewNav, so the map keeps the page.
	// The views are URLs, so the options are links and the menu is a disclosure,
	// not an ARIA menu.
	let { view, floating = false }: { view: 'mine' | 'routes' | 'segments'; floating?: boolean } = $props();

	const options = $derived([
		{ view: 'mine', href: '/routes', label: m('exploreMap.viewMine'), icon: 'bookmarks' },
		{ view: 'routes', href: '/routes?tab=explore', label: m('exploreMap.viewRoutes'), icon: 'route' },
		{ view: 'segments', href: '/segments', label: m('exploreMap.viewSegments'), icon: 'timeline' },
	] as const);
	const current = $derived(options.find((o) => o.view === view) ?? options[0]);

	let open = $state(false);
	let root: HTMLDivElement | undefined = $state();

	$effect(() => {
		if (!open) return;
		const onDown = (e: PointerEvent) => {
			if (root && !root.contains(e.target as Node)) open = false;
		};
		const onKey = (e: KeyboardEvent) => {
			if (e.key === 'Escape') {
				open = false;
				root?.querySelector<HTMLButtonElement>('button')?.focus();
			}
		};
		document.addEventListener('pointerdown', onDown);
		document.addEventListener('keydown', onKey);
		return () => {
			document.removeEventListener('pointerdown', onDown);
			document.removeEventListener('keydown', onKey);
		};
	});
</script>

<div class="view-menu" class:floating bind:this={root} data-testid="routes-view-menu">
	<button
		type="button"
		class="trigger"
		aria-expanded={open}
		aria-controls="routes-view-menu-list"
		aria-label={m('exploreMap.viewMenuLabel', { view: current.label })}
		onclick={() => (open = !open)}
		data-testid="routes-view-menu-button"
	>
		<span class="label">{current.label}</span>
		<span class="material-symbols" aria-hidden="true">{open ? 'expand_less' : 'expand_more'}</span>
	</button>
	{#if open}
		<ul id="routes-view-menu-list" class="list">
			{#each options as o (o.view)}
				<li>
					<a
						href={o.href}
						class:current={o.view === view}
						aria-current={o.view === view ? 'page' : undefined}
						onclick={() => (open = false)}
						data-testid="routes-view-menu-{o.view}"
					>
						<span class="material-symbols" aria-hidden="true">{o.icon}</span>
						<span>{o.label}</span>
					</a>
				</li>
			{/each}
		</ul>
	{/if}
</div>

<style>
	.view-menu {
		position: relative;
		min-width: 0;
	}
	.trigger {
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
		max-width: 100%;
		min-height: var(--tap-target-min);
		padding: var(--space-xs) var(--space-sm) var(--space-xs) var(--space-md);
		border: 1px solid var(--color-border);
		border-radius: 9999px;
		background: var(--color-surface);
		color: var(--color-text);
		font-size: 1rem;
		font-weight: 600;
		cursor: pointer;
	}
	.floating .trigger {
		box-shadow: var(--shadow-md);
	}
	.label {
		overflow-wrap: anywhere;
		text-align: start;
	}
	.trigger:focus-visible,
	.list a:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}
	.list {
		position: absolute;
		inset-inline-start: 0;
		top: calc(100% + var(--space-xs));
		z-index: 30;
		min-width: 14rem;
		max-width: calc(100vw - 2 * var(--space-md));
		margin: 0;
		padding: var(--space-xs);
		list-style: none;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		box-shadow: var(--shadow-lg);
	}
	.list a {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		min-height: var(--tap-target-min);
		padding: var(--space-xs) var(--space-sm);
		border-radius: var(--radius-sm);
		color: var(--color-text);
		text-decoration: none;
	}
	.list a:hover {
		background: var(--color-bg-secondary);
	}
	.list a.current {
		color: var(--color-primary);
		font-weight: 600;
	}
</style>
