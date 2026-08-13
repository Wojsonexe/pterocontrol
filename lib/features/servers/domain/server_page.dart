import 'server.dart';

/// One page of a server listing.
///
/// Pages are 1-indexed, matching the Pterodactyl Client API's `?page=`
/// query parameter (see `ServerRepository`/`ServersApi`).
class ServerPage {
  const ServerPage({required this.servers, required this.page, required this.totalPages});

  final List<Server> servers;
  final int page;
  final int totalPages;

  bool get hasNextPage => page < totalPages;
}
