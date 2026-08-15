import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../instances/application/instance_api_client_provider.dart';
import '../data/file_repository_impl.dart';
import '../data/files_api.dart';
import '../domain/file_repository.dart';
import '../domain/file_target.dart';

/// [FilesApi] scoped to one instance, built on that instance's
/// [instanceApiClientProvider] — same seam `ServersApi`/`ConsoleApi` use.
final _filesApiProvider = Provider.autoDispose.family<FilesApi, String>((ref, instanceId) {
  final client = ref.watch(instanceApiClientProvider(instanceId));
  return FilesApi(client);
});

/// The real [FileRepository] for one `(instanceId, serverIdentifier)`
/// pair, keyed by [FileTarget].
///
/// `autoDispose`: a file manager session (and, on disposal, any transfer
/// still running — see `FileManagerController.build`) is torn down the
/// moment nothing is watching it, the same lifecycle
/// `consoleRepositoryProvider` already applies to the WebSocket.
final fileRepositoryProvider = Provider.autoDispose.family<FileRepository, FileTarget>((ref, target) {
  final api = ref.watch(_filesApiProvider(target.instanceId));
  final client = ref.watch(instanceApiClientProvider(target.instanceId));
  return FileRepositoryImpl(api: api, client: client, serverIdentifier: target.serverIdentifier);
});
