-- Shipped in the companion image at /var/opt/mssql-init/00-workspace.sql and
-- NOT applied automatically. SQL Server's container has no init-script hook --
-- there is no equivalent of PostgreSQL's /docker-entrypoint-initdb.d -- and the
-- image this one is built FROM is a byte-identical mirror of Microsoft's, so a
-- hook cannot be added upstream either. Apply it once from the workspace:
--
--   sqlcmd -S "$DB_HOST,$DB_PORT" -U sa -P 'DemoPass-123' -C \
--          -i /var/opt/mssql-init/00-workspace.sql
--
-- or, with no client installed, from a .NET program through
-- Microsoft.Data.SqlClient against the same host and port. `-C' trusts the
-- engine's self-signed certificate, which is what a workspace database has.
--
-- A small schema the workspace can query straight away, so `SELECT COUNT(*)
-- FROM workspace.notes' answers on a fresh volume and the developer's first
-- session is not against nothing.
--
-- WRITTEN TO BE RUN TWICE. Every statement checks first: the volume outlives
-- the workspace, so this file meets an already-seeded database whenever a
-- developer re-applies it after a rebuild.
IF DB_ID('demodb') IS NULL
    CREATE DATABASE demodb;
GO

USE demodb;
GO

IF SCHEMA_ID('workspace') IS NULL
    EXEC('CREATE SCHEMA workspace');
GO

-- T-SQL, not the PostgreSQL this seed used to ship: bigserial becomes BIGINT
-- IDENTITY, timestamptz becomes DATETIMEOFFSET, text becomes NVARCHAR(MAX),
-- and neither CREATE SCHEMA nor CREATE TABLE takes IF NOT EXISTS.
IF OBJECT_ID('workspace.notes') IS NULL
    CREATE TABLE workspace.notes (
        id         BIGINT IDENTITY(1,1) PRIMARY KEY,
        created_at DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
        body       NVARCHAR(MAX)  NOT NULL
    );
GO

IF NOT EXISTS (SELECT 1 FROM workspace.notes)
    INSERT INTO workspace.notes (body) VALUES
        (N'This database was built by the forge from services/db in this repository.'),
        (N'It persists on a host volume beside the workspace; `make stop` keeps it.'),
        (N'Reach it from the workspace at $DB_HOST:$DB_PORT as sa / DemoPass-123.');
GO
