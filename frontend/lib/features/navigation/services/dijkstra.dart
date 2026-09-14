/// Minimal Dijkstra's-algorithm shortest-path finder for small weighted
/// graphs. Deliberately a plain O(V^2) scan rather than a heap-based
/// version — used to pick the shortest-distance route among OSRM's
/// returned alternatives (see OsrmRoutingService._shortest), where the
/// graph never has more than a handful of nodes.
class DijkstraResult {
  final List<String> path;
  final double distance;
  const DijkstraResult(this.path, this.distance);
}

class Dijkstra {
  final Map<String, Map<String, double>> _adjacency = {};

  void addEdge(String from, String to, double weight) {
    _adjacency.putIfAbsent(from, () => {})[to] = weight;
  }

  DijkstraResult? shortestPath(String start, String end) {
    final dist = <String, double>{start: 0};
    final prev = <String, String>{};
    final unvisited = <String>{
      start,
      ..._adjacency.keys,
      for (final edges in _adjacency.values) ...edges.keys,
    };

    while (unvisited.isNotEmpty) {
      String? current;
      for (final node in unvisited) {
        if (dist[node] == null) continue;
        if (current == null || dist[node]! < dist[current]!) current = node;
      }
      if (current == null) break; // remaining nodes are unreachable from start
      unvisited.remove(current);
      if (current == end) break;

      for (final entry in (_adjacency[current] ?? const {}).entries) {
        final alt = dist[current]! + entry.value;
        if (alt < (dist[entry.key] ?? double.infinity)) {
          dist[entry.key] = alt;
          prev[entry.key] = current;
        }
      }
    }

    if (dist[end] == null) return null;
    final path = <String>[end];
    while (path.last != start) {
      final p = prev[path.last];
      if (p == null) return null;
      path.add(p);
    }
    return DijkstraResult(path.reversed.toList(), dist[end]!);
  }
}
