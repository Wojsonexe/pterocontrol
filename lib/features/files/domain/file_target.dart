/// Identifies a single server within a single Pterodactyl instance — the
/// key a file manager session is scoped by.
///
/// Structurally identical to `ConsoleTarget`
/// (`features/console/domain/console_target.dart`) on purpose, not
/// imported from it — see that file's own doc comment for why each
/// feature defines its own copy of this shape instead of sharing one
/// nominal type across feature boundaries.
typedef FileTarget = ({String instanceId, String serverIdentifier});
