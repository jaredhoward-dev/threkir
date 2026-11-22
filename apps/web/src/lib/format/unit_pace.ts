/// Pace, speed and plan-distance labels in an explicit unit.
///
/// Pure (explicit unit + locale) so it unit-tests without the Svelte compiler;
/// `formatPace`, `formatPaceNoSuffix`, `formatSpeed`, `fmtKm`, `fmtPace` and
/// `distanceInPreferred` in units.svelte.ts supply the preference signal. The
/// Dart counterparts are `UnitFormat.pace` / `UnitFormat.speed` in
/// apps/mobile_android/lib/preferences.dart.

import { formatDecimal } from './number';
import { isMeaningfulPace, paceMinutesSeconds } from './pace_format';

const METRES_PER_MILE = 1609.344;

type Unit = 'km' | 'mi';

function secPerUnit(seconds: number, metres: number, unit: Unit): number {
	const perKm = seconds / (metres / 1000);
	return unit === 'mi' ? perKm * (METRES_PER_MILE / 1000) : perKm;
}

/// "5:30 /km" — '--:--' when the pair can't make a pace.
export function formatPaceIn(seconds: number, metres: number, unit: Unit): string {
	if (!isMeaningfulPace(seconds, metres)) return '--:--';
	return `${paceMinutesSeconds(secPerUnit(seconds, metres, unit))} /${unit}`;
}

export function formatPaceNoSuffixIn(seconds: number, metres: number, unit: Unit): string {
	if (!isMeaningfulPace(seconds, metres)) return '--:--';
	return paceMinutesSeconds(secPerUnit(seconds, metres, unit));
}

/// "12.0 km/h" / "7.5 mph". mph is derived from the exact mile, as the Dart
/// twin does, so both platforms round the same value.
export function formatSpeedIn(seconds: number, metres: number, unit: Unit, locale?: string): string {
	if (!isMeaningfulPace(seconds, metres)) return '--';
	const kmh = (metres / seconds) * 3.6;
	if (unit === 'mi') return `${formatDecimal(kmh / (METRES_PER_MILE / 1000), 1, locale)} mph`;
	return `${formatDecimal(kmh, 1, locale)} km/h`;
}

export function distanceIn(metres: number, unit: Unit): { value: number; unit: Unit } {
	return unit === 'mi' ? { value: metres / METRES_PER_MILE, unit: 'mi' } : { value: metres / 1000, unit: 'km' };
}

/// Fixed-digit plan distance: "10.0 km" / "6.2 mi"; '—' for no value.
export function fmtKmIn(metres: number | null | undefined, unit: Unit, locale?: string, digits = 1): string {
	if (metres == null) return '—';
	return `${formatDecimal(distanceIn(metres, unit).value, digits, locale)} ${unit}`;
}

/// Plan pace from canonical seconds-per-km: "5:00/km" / "8:03/mi"; '—' for
/// none, zero, negative or non-finite.
export function fmtPaceIn(secPerKm: number | null | undefined, unit: Unit): string {
	if (secPerKm == null || !Number.isFinite(secPerKm) || secPerKm <= 0) return '—';
	const sec = unit === 'mi' ? secPerKm * (METRES_PER_MILE / 1000) : secPerKm;
	return `${paceMinutesSeconds(sec)}/${unit}`;
}
