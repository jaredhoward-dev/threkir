<script lang="ts">
	import { m } from '#lib/i18n/store.svelte.ts';

	// What an empty view of the map says instead of nothing (decisions § 2611):
	// that there is nothing here, and the ways back to something.
	let {
		title,
		onzoomout,
		nearest = null,
		onclearfilters,
	}: {
		title: string;
		onzoomout: () => void;
		nearest?: { name: string; onclick: () => void } | null;
		/// Set while a filter is narrowing the map.
		onclearfilters?: () => void;
	} = $props();
</script>

<div class="empty-view" role="status" data-testid="explore-empty-view">
	<p class="title">{title}</p>
	<div class="actions">
		<button type="button" class="btn btn-outline btn-sm" onclick={onzoomout} data-testid="explore-zoom-out">
			<span class="material-symbols" aria-hidden="true">zoom_out</span>
			{m('exploreMap.zoomOut')}
		</button>
		{#if onclearfilters}
			<button type="button" class="btn btn-outline btn-sm" onclick={onclearfilters}>
				{m('routeExplorer.clearFilters')}
			</button>
		{/if}
		{#if nearest}
			<button type="button" class="btn btn-outline btn-sm nearest" onclick={nearest.onclick} data-testid="explore-nearest">
				{m('exploreMap.nearest', { name: nearest.name })}
			</button>
		{/if}
	</div>
</div>

<style>
	.empty-view {
		max-width: min(100%, 24rem);
		padding: var(--space-sm) var(--space-md);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		background: var(--color-surface);
		box-shadow: var(--shadow-md);
		text-align: center;
	}
	.title {
		margin: 0 0 var(--space-sm);
		font-weight: 700;
	}
	.actions {
		display: flex;
		flex-wrap: wrap;
		justify-content: center;
		gap: var(--space-xs);
	}
	.nearest {
		overflow-wrap: anywhere;
		white-space: normal;
		text-align: start;
	}
</style>
