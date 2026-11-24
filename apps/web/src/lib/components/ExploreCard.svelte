<script lang="ts">
	import type { Snippet } from 'svelte';
	import { m } from '#lib/i18n/store.svelte.ts';

	// The card a tapped route or segment opens over the map's foot (decisions
	// § 2611): the whole name, wrapping rather than cut, an "Official course"
	// line under it rather than a badge on the title line, one stats line, and
	// the actions. Close returns to the plain map.
	let {
		name,
		official = false,
		detail,
		stats,
		actions,
		onclose,
		testid,
	}: {
		name: string;
		official?: boolean;
		/// A second line under the name, such as a segment's region.
		detail?: string | null;
		stats: string;
		actions: Snippet;
		onclose: () => void;
		testid?: string;
	} = $props();
</script>

<div class="explore-card" role="region" aria-label={name} data-testid={testid}>
	<div class="head">
		<h3 class="name">{name}</h3>
		<button type="button" class="close" onclick={onclose} aria-label={m('modal.close')} data-testid="explore-card-close">
			<span class="material-symbols" aria-hidden="true">close</span>
		</button>
	</div>
	{#if official}
		<p class="official" data-testid="explore-card-official">
			<span class="material-symbols" aria-hidden="true">verified</span>
			{m('exploreMap.officialCourse')}
		</p>
	{/if}
	{#if detail}<p class="detail">{detail}</p>{/if}
	<p class="stats">{stats}</p>
	<div class="actions">{@render actions()}</div>
</div>

<style>
	.explore-card {
		width: min(100%, 32rem);
		padding: var(--space-md);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		background: var(--color-surface);
		box-shadow: var(--shadow-lg);
	}
	.head {
		display: flex;
		align-items: flex-start;
		gap: var(--space-sm);
	}
	.name {
		flex: 1 1 auto;
		min-width: 0;
		margin: 0;
		padding-top: var(--space-xs);
		font-size: 1.1rem;
		font-weight: 700;
		overflow-wrap: anywhere;
	}
	.close {
		flex: none;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: var(--tap-target-min);
		height: var(--tap-target-min);
		margin: calc(-1 * var(--space-xs));
		border: none;
		border-radius: 50%;
		background: none;
		color: var(--color-text-secondary);
		cursor: pointer;
	}
	.close:hover {
		background: var(--color-bg-secondary);
	}
	.official {
		display: flex;
		align-items: center;
		gap: var(--space-xs);
		margin: var(--space-2xs) 0 0;
		color: var(--color-primary);
		font-size: 0.9rem;
		font-weight: 600;
	}
	.official .material-symbols {
		font-size: 1.1rem;
	}
	.detail,
	.stats {
		margin: var(--space-2xs) 0 0;
		color: var(--color-text-secondary);
		font-size: 0.9rem;
	}
	.actions {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-sm);
		margin-top: var(--space-md);
	}
</style>
