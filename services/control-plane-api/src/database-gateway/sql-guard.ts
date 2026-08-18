import { BadRequestException } from '@nestjs/common';

// Deliberately no DDL (CREATE/ALTER/DROP/TRUNCATE/RENAME) and no privilege
// statements (GRANT/REVOKE) - the user chose full DML (SELECT/INSERT/
// UPDATE/DELETE) for the Database Gateway but explicitly excluded DDL, see
// IMPLEMENTATION_STATUS.md. This is a pragmatic keyword/shape guard, not a
// real SQL parser - it catches the statement types we decided are out of
// scope and accidental multi-statement submissions, not every conceivable
// abuse of raw SQL. Executing arbitrary DML as an authenticated owner/admin
// is the accepted risk of this feature; this guard's job is only to enforce
// the DDL exclusion and stop obviously-wrong input before it reaches MySQL.
const FORBIDDEN_KEYWORDS = [
  'CREATE',
  'ALTER',
  'DROP',
  'TRUNCATE',
  'RENAME',
  'GRANT',
  'REVOKE',
];

const ALLOWED_LEADING_KEYWORDS = ['SELECT', 'INSERT', 'UPDATE', 'DELETE'];

export function validateSql(sql: string): void {
  const trimmed = sql.trim();
  if (trimmed.length === 0) {
    throw new BadRequestException('sql must not be empty');
  }

  const withoutTrailingSemicolon = trimmed.endsWith(';') ? trimmed.slice(0, -1) : trimmed;
  if (withoutTrailingSemicolon.includes(';')) {
    throw new BadRequestException(
      'Only a single SQL statement is allowed per request (found a semicolon before the end)',
    );
  }

  const leadingKeywordMatch = /^([a-zA-Z]+)/.exec(withoutTrailingSemicolon);
  const leadingKeyword = leadingKeywordMatch?.[1]?.toUpperCase();
  if (!leadingKeyword || !ALLOWED_LEADING_KEYWORDS.includes(leadingKeyword)) {
    throw new BadRequestException(
      `Statement must start with one of ${ALLOWED_LEADING_KEYWORDS.join(', ')}`,
    );
  }

  const upper = withoutTrailingSemicolon.toUpperCase();
  for (const forbidden of FORBIDDEN_KEYWORDS) {
    if (new RegExp(`\\b${forbidden}\\b`).test(upper)) {
      throw new BadRequestException(`Statement must not contain ${forbidden} (DDL is not allowed)`);
    }
  }
}
