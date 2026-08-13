import 'package:meta/meta.dart';

import '../domain/server.dart';

/// State exposed by `ServerListController` for one instance's server list.
@immutable
class ServerListState {
  const ServerListState({
    required this.servers,
    required this.page,
    required this.totalPages,
    this.isLoadingNextPage = false,
  });

  final List<Server> servers;
  final int page;
  final int totalPages;

  /// Whether a `loadNextPage()` call is currently in flight. The initial
  /// load and `refresh()` are represented by the provider's own
  /// loading/error `AsyncValue` state instead — this flag only covers
  /// "append more to an already-successful list".
  final bool isLoadingNextPage;

  bool get hasNextPage => page < totalPages;

  ServerListState copyWith({
    List<Server>? servers,
    int? page,
    int? totalPages,
    bool? isLoadingNextPage,
  }) {
    return ServerListState(
      servers: servers ?? this.servers,
      page: page ?? this.page,
      totalPages: totalPages ?? this.totalPages,
      isLoadingNextPage: isLoadingNextPage ?? this.isLoadingNextPage,
    );
  }
}
