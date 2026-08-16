import { BadRequestException } from '@nestjs/common';
import { validateSql } from './sql-guard';

describe('validateSql', () => {
  it.each(['SELECT * FROM players', 'select id from players', '  SELECT 1  '])(
    'allows a single SELECT statement: %s',
    (sql) => {
      expect(() => validateSql(sql)).not.toThrow();
    },
  );

  it.each([
    "INSERT INTO players (name) VALUES ('a')",
    "UPDATE players SET name = 'b' WHERE id = 1",
    'DELETE FROM players WHERE id = 1',
  ])('allows DML statements: %s', (sql) => {
    expect(() => validateSql(sql)).not.toThrow();
  });

  it('allows exactly one trailing semicolon', () => {
    expect(() => validateSql('SELECT * FROM players;')).not.toThrow();
  });

  it('rejects an empty statement', () => {
    expect(() => validateSql('   ')).toThrow(BadRequestException);
  });

  it('rejects stacked statements', () => {
    expect(() => validateSql('SELECT 1; DROP TABLE players')).toThrow(BadRequestException);
  });

  it.each(['CREATE TABLE x (id INT)', 'ALTER TABLE players ADD COLUMN x INT', 'DROP TABLE players', 'TRUNCATE TABLE players', 'GRANT ALL ON *.* TO x', 'REVOKE ALL ON *.* FROM x'])(
    'rejects DDL/privilege statements: %s',
    (sql) => {
      expect(() => validateSql(sql)).toThrow(BadRequestException);
    },
  );

  it('rejects a statement that does not start with an allowed keyword', () => {
    expect(() => validateSql('SHOW TABLES')).toThrow(BadRequestException);
  });

  it('rejects an UPDATE that smuggles DROP as a later clause', () => {
    expect(() => validateSql('UPDATE players SET name = (DROP TABLE x)')).toThrow(
      BadRequestException,
    );
  });
});
