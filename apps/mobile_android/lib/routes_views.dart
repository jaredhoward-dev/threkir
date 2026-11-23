import 'package:flutter/widgets.dart';

/// The Routes tab's views: Mine (the runner's own and saved routes), Explore
/// routes (public routes on a map) or Explore segments (the segment catalogue
/// on a map). One menu names and switches all three (decisions § 2611).
///
/// The segment catalogue was a Fitness tab of its own until issue #1374
/// (owner decision 1) folded it into Routes, so one value names the view, and
/// a link can open it through the shell's channel
/// (`fitness_surface_requests.dart`).
enum RoutesShow {
  mine,
  routes,
  segments;

  bool get isExplore => this != RoutesShow.mine;
}

/// What the Routes tab hands each Explore body: the view menu, which floats
/// on the body's map. Null when the body is mounted on its own.
@immutable
class RoutesExploreChrome {
  const RoutesExploreChrome({required this.menu});

  final Widget menu;
}
