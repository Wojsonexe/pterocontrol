import '../../../core/error/result.dart';
import '../../../core/network/pterodactyl_api_client.dart';
import '../../../core/network/pterodactyl_envelope.dart';
import 'file_entry_dto.dart';

/// Knows the Pterodactyl Client API's Files endpoints
/// (`/api/client/servers/{server}/files/...`).
///
/// Built on top of a [PterodactylApiClient] already scoped to one
/// instance — same seam `ServersApi`/`ConsoleApi` use, so this inherits
/// the same instance-isolation guarantees without adding any new ones.
///
/// HTTP methods and request/response shapes below follow the Client
/// API's actual route table and controller contracts (`FileController` —
/// `list`/`contents`/`download`/`upload` are `GET`, `rename` is `PUT`,
/// everything else that mutates is `POST`) — not guessed from what
/// "should" be RESTful. Two real API facts that shape this class:
///
/// - There is no dedicated "move" endpoint. `rename` (`PUT
///   .../files/rename`, body `{"root": "...", "files": [{"from": "...",
///   "to": "..."}]}`) is the *same* endpoint for both a same-directory
///   rename and a cross-directory move — Wings only cares whether `to`
///   differs from `from`, not whether it changes the leaf name or the
///   directory or both. [rename] exposes exactly this one operation;
///   `FileRepository` is where "rename" vs. "move" become two
///   user-facing verbs over the same call — see that class.
/// - `copy` (`POST .../files/copy`, body `{"location": "..."}`) only
///   ever takes **one** file — there is no bulk-copy endpoint. A
///   multi-select "copy" action does not exist in the real Client API;
///   see `FileRepository`'s doc comment for how bulk "download" is
///   still made to work (via `compress` + a single `download`) without
///   inventing an endpoint that is not there.
class FilesApi {
  const FilesApi(this._client);

  final PterodactylApiClient _client;

  /// `GET .../files/list?directory=...` — every entry directly inside
  /// [directory] (not recursive).
  Future<Result<List<FileEntryDto>>> list(String serverIdentifier, {required String directory}) {
    return _client.get<List<FileEntryDto>>(
      '/api/client/servers/$serverIdentifier/files/list',
      queryParameters: {'directory': directory},
      parser: (data) {
        final (items, _) = PterodactylEnvelope.unwrapList(data);
        return items.map(FileEntryDto.fromJson).toList(growable: false);
      },
    );
  }

  /// `GET .../files/contents?file=...` — the raw contents of [file] as
  /// plain text. Callers must only call this for a
  /// [FileEntry.isEditable] entry — Wings does not itself refuse to
  /// return an arbitrary binary's bytes here, this app simply never asks
  /// for one (see `FileEditorController`).
  Future<Result<String>> getContents(String serverIdentifier, {required String file}) {
    return _client.getRawText(
      '/api/client/servers/$serverIdentifier/files/contents',
      queryParameters: {'file': file},
    );
  }

  /// `POST .../files/write?file=...`, raw `text/plain` body — overwrites
  /// (or creates, if it does not yet exist) [file] with [content].
  Future<Result<void>> writeContents(String serverIdentifier, {required String file, required String content}) {
    return _client.postRawText(
      '/api/client/servers/$serverIdentifier/files/write',
      content,
      queryParameters: {'file': file},
    );
  }

  /// `POST .../files/create-folder`, body `{"root": "...", "name": "..."}`.
  Future<Result<void>> createFolder(String serverIdentifier, {required String root, required String name}) {
    return _client.post<void>(
      '/api/client/servers/$serverIdentifier/files/create-folder',
      data: {'root': root, 'name': name},
      parser: (_) {},
    );
  }

  /// `PUT .../files/rename`, body `{"root": "...", "files": [{"from":
  /// "...", "to": "..."}, ...]}` — bulk-capable (multiple entries in one
  /// request), which is what makes multi-select "Move" possible without
  /// N separate requests. See this class's doc comment for why "rename"
  /// and "move" are the same wire call.
  Future<Result<void>> rename(
    String serverIdentifier, {
    required String root,
    required List<({String from, String to})> files,
  }) {
    return _client.put<void>(
      '/api/client/servers/$serverIdentifier/files/rename',
      data: {
        'root': root,
        'files': [for (final f in files) {'from': f.from, 'to': f.to}],
      },
      parser: (_) {},
    );
  }

  /// `POST .../files/copy`, body `{"location": "..."}` — copies exactly
  /// one file; Wings picks the resulting name itself (a " copy" suffix,
  /// de-duplicated if that also exists). No `to` — the destination is
  /// always alongside the source.
  Future<Result<void>> copy(String serverIdentifier, {required String location}) {
    return _client.post<void>(
      '/api/client/servers/$serverIdentifier/files/copy',
      data: {'location': location},
      parser: (_) {},
    );
  }

  /// `POST .../files/compress`, body `{"root": "...", "files": [...]}` —
  /// archives the given entries (relative to `root`) into one new
  /// `.tar.gz` alongside them, returning that archive's own listing
  /// entry so the caller can show/download it immediately without a
  /// full directory re-list.
  Future<Result<FileEntryDto>> compress(String serverIdentifier, {required String root, required List<String> files}) {
    return _client.post<FileEntryDto>(
      '/api/client/servers/$serverIdentifier/files/compress',
      data: {'root': root, 'files': files},
      parser: (data) => FileEntryDto.fromJson(PterodactylEnvelope.unwrapItem(data)),
    );
  }

  /// `POST .../files/decompress`, body `{"root": "...", "file": "..."}`.
  Future<Result<void>> decompress(String serverIdentifier, {required String root, required String file}) {
    return _client.post<void>(
      '/api/client/servers/$serverIdentifier/files/decompress',
      data: {'root': root, 'file': file},
      parser: (_) {},
    );
  }

  /// `POST .../files/delete`, body `{"root": "...", "files": [...]}` —
  /// bulk-capable, one request for a whole multi-select deletion.
  Future<Result<void>> delete(String serverIdentifier, {required String root, required List<String> files}) {
    return _client.post<void>(
      '/api/client/servers/$serverIdentifier/files/delete',
      data: {'root': root, 'files': files},
      parser: (_) {},
    );
  }

  /// `GET .../files/download?file=...` — **not** the file itself: a
  /// one-time signed URL (served directly by Wings, not the Panel) that
  /// is only valid briefly. Callers must fetch it immediately before
  /// downloading, never cache it — see `FileRepository.downloadFile`.
  Future<Result<String>> getDownloadUrl(String serverIdentifier, {required String file}) {
    return _client.get<String>(
      '/api/client/servers/$serverIdentifier/files/download',
      queryParameters: {'file': file},
      parser: (data) => PterodactylEnvelope.unwrapItem(data)['url'] as String,
    );
  }

  /// `GET .../files/upload` — same signed-URL pattern as
  /// [getDownloadUrl], for the *other* direction: the actual upload is a
  /// separate `multipart/form-data POST` straight to the returned URL
  /// (see `PterodactylApiClient.uploadMultipart`), not to this endpoint.
  Future<Result<String>> getUploadUrl(String serverIdentifier) {
    return _client.get<String>(
      '/api/client/servers/$serverIdentifier/files/upload',
      parser: (data) => PterodactylEnvelope.unwrapItem(data)['url'] as String,
    );
  }
}
