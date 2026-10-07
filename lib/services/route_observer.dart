import 'package:flutter/material.dart';

/// Shared app-wide RouteObserver so screens can refetch their data whenever
/// they become visible again (RouteAware.didPopNext), the closest Flutter
/// equivalent to web's React Query refetchOnMount — matches neolingo's
/// daily-streak page, which has no live subscription of its own and simply
/// refetches every time its query re-subscribes.
final RouteObserver<ModalRoute<void>> appRouteObserver = RouteObserver<ModalRoute<void>>();
