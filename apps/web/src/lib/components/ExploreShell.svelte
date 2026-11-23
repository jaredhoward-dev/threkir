<script lang="ts">
	import type { Snippet } from 'svelte';
	import { onMount } from 'svelte';
	import { m } from '#lib/i18n/store.svelte.ts';
	import RoutesViewMenu from './RoutesViewMenu.svelte';

	// The map-first layout Explore routes and Explore segments share (decisions
	// § 2611). At phone width the map is the page: the view menu, Search and
	// Filters float on its top edge, its own buttons stack at the end edge above
	// a "List · N" pill, and a tapped route's card floats over its foot. The list
	// is its own view (`?view=list`), so browser back returns to the map. Wider,
	// the list stands beside the map and the pill is not needed.
	let {
		view,
		listOpen,
		listHref,
		listLabel,
		listTitle,
		onbacktomap,
		onopenlist,
		map,
		toolbar,
		mapButtons,
		overlay,
		card,
		cardOpen = false,
		list,
	}: {
		view: 'routes' | 'segments';
		listOpen: boolean;
		listHref: string;
		/// "List · 12 routes".
		listLabel: string;
		listTitle: string;
		onbacktomap: () => void;
		onopenlist?: () => void;
		map: Snippet;
		/// Search and Filters, after the view menu on the map's top edge.
		toolbar: Snippet;
		mapButtons?: Snippet;
		/// Over the map's middle: the empty-view note, the "Which route?" list,
		/// the search results.
		overlay?: Snippet;
		card?: Snippet;
		/// Whether [card] has something to show; the List pill gives way to it.
		cardOpen?: boolean;
		list: Snippet;
	} = $props();

	let root: HTMLDivElement | undefined = $state();
	let height = $state(560);

	onMount(() => {
		const measure = () => {
			if (!root) return;
			const top = root.getBoundingClientRect().top + window.scrollY;
			height = Math.max(420, window.innerHeight - top - 16);
		};
		measure();
		window.addEventListener('resize', measure);
		return () => window.removeEventListener('resize', measure);
	});
</script>

<div class="explore" class:list-open={listOpen} bind:this={root} style:--explore-h="{height}px" data-testid="explore-{view}">
	<section class="list-pane" aria-label={listTitle} data-testid="explore-list">
		<header class="list-head">
			<button type="button" class="back" onclick={onbacktomap} data-testid="explore-back-to-map">
				<span class="material-symbols" aria-hidden="true">arrow_back</span>
				<span class="visually-hidden">{m('exploreMap.backToMap')}</span>
			</button>
			<h2>{listTitle}</h2>
		</header>
		{@render list()}
	</section>

	<div class="map-pane">
		{@render map()}
		<div class="top-bar">
			<div class="menu-slot"><RoutesViewMenu {view} floating /></div>
			<div class="tools">{@render toolbar()}</div>
		</div>
		{#if overlay}<div class="overlay">{@render overlay()}</div>{/if}
		<div class="foot">
			{#if mapButtons}<div class="map-buttons">{@render mapButtons()}</div>{/if}
			{#if card && cardOpen}
				{@render card()}
			{:else}
				<a class="list-pill" href={listHref} onclick={() => onopenlist?.()} data-testid="explore-list-pill">
					<span class="material-symbols" aria-hidden="true">list</span>
					{listLabel}
				</a>
			{/if}
		</div>
	</div>
</div>

<style>
	.explore {
		display: grid;
		grid-template-columns: minmax(18rem, 26rem) 1fr;
		gap: var(--space-md);
		height: var(--explore-h);
	}

	.list-pane {
		min-height: 0;
		overflow-y: auto;
		padding-inline-end: var(--space-2xs);
	}

	.list-head {
		display: none;
		align-items: center;
		gap: var(--space-sm);
		margin-bottom: var(--space-md);
	}
	.list-head h2 {
		font-size: 1.25rem;
		font-weight: 700;
		margin: 0;
	}

	.back {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: var(--tap-target-min);
		height: var(--tap-target-min);
		border: none;
		border-radius: 50%;
		background: none;
		color: var(--color-text);
		cursor: pointer;
	}
	.back:hover {
		background: var(--color-bg-secondary);
	}

	.map-pane {
		position: relative;
		min-height: 0;
		overflow: hidden;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
	}

	.top-bar {
		position: absolute;
		inset-inline: var(--space-sm);
		top: var(--space-sm);
		display: flex;
		align-items: flex-start;
		gap: var(--space-sm);
		pointer-events: none;
		z-index: 5;
	}
	.top-bar > * {
		pointer-events: auto;
	}
	.menu-slot {
		display: none;
		min-width: 0;
		flex: 1 1 auto;
	}
	.tools {
		display: flex;
		gap: var(--space-xs);
		margin-inline-start: auto;
		/* Clear of MapLibre's zoom buttons at the top end. */
		margin-inline-end: 3rem;
	}

	.overlay {
		position: absolute;
		inset-inline: var(--space-sm);
		top: calc(var(--tap-target-min) + 2 * var(--space-sm));
		display: flex;
		justify-content: center;
		z-index: 6;
		pointer-events: none;
	}
	.overlay > :global(*) {
		pointer-events: auto;
	}

	.foot {
		position: absolute;
		inset-inline: var(--space-sm);
		bottom: var(--space-md);
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-sm);
		z-index: 5;
		pointer-events: none;
	}
	.foot > :global(*) {
		pointer-events: auto;
	}
	.map-buttons {
		align-self: flex-end;
		display: flex;
		flex-direction: column;
		align-items: flex-end;
		gap: var(--space-xs);
	}

	.list-pill {
		display: none;
		align-items: center;
		gap: var(--space-xs);
		min-height: var(--tap-target-min);
		padding: var(--space-xs) var(--space-lg);
		border-radius: 9999px;
		background: var(--color-primary);
		color: var(--color-on-primary, white);
		font-weight: 700;
		text-decoration: none;
		box-shadow: var(--shadow-lg);
	}
	.list-pill:focus-visible {
		outline: 2px solid var(--color-text);
		outline-offset: 2px;
	}

	@media (max-width: 40rem) {
		.explore {
			grid-template-columns: 1fr;
		}
		.list-pane {
			display: none;
		}
		.list-open .list-pane {
			display: block;
		}
		.list-open .map-pane {
			display: none;
		}
		.list-head {
			display: flex;
		}
		.menu-slot {
			display: block;
		}
		.tools {
			margin-inline-end: 0;
		}
		.list-pill {
			display: inline-flex;
		}
		/* Pinch zooms on a phone; the top edge is the view menu's. */
		.map-pane :global(.maplibregl-ctrl-top-right) {
			display: none;
		}
	}
</style>
