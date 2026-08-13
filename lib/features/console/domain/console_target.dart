/// Identifies a single server within a single Pterodactyl instance — the
/// key a console connection is scoped by.
///
/// Deliberately not imported from `features/servers/application/` (which
/// has a structurally identical record for the same reason): Dart records
/// are structurally typed, so this and that one are already
/// interchangeable wherever the field names/types match — there is no
/// technical need to share one nominal type across two features'
/// application layers, and importing across them would be an odd
/// dependency for a plain data shape.
typedef ConsoleTarget = ({String instanceId, String serverIdentifier});
