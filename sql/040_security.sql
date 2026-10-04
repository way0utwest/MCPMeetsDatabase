/* Least-privilege login for Data API builder. EXECUTE on the public procedures, SELECT on three tables, nothing else. */
USE master;
GO
IF NOT EXISTS (SELECT 1 FROM sys.sql_logins WHERE name = N'dab_app')
    CREATE LOGIN dab_app WITH PASSWORD = N'Dab_strong_Passw0rd', CHECK_POLICY = ON;  -- change me, or use Entra managed identity in Azure
GO
USE ShiftSwap;
GO
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'dab_app')
    CREATE USER dab_app FOR LOGIN dab_app;
GO

/* Role so grants are reviewable in one place. */
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'shiftswap_api' AND type = 'R')
    CREATE ROLE shiftswap_api;
GO
ALTER ROLE shiftswap_api ADD MEMBER dab_app;
GO

/* Read-only tables for GraphQL schedule grids and people pickers. */
GRANT SELECT ON dbo.Job      TO shiftswap_api;
GRANT SELECT ON dbo.Employee TO shiftswap_api;   -- DAB config excludes ManagerId/IsActive from the API surface
GRANT SELECT ON dbo.Shift    TO shiftswap_api;

/* No direct access to Vacation, ShiftSwapRequest, AuditLog. Procedures only. */

GRANT EXECUTE ON dbo.Vacation_Request   TO shiftswap_api;
GRANT EXECUTE ON dbo.Vacation_Approve   TO shiftswap_api;
GRANT EXECUTE ON dbo.Vacation_Cancel    TO shiftswap_api;
GRANT EXECUTE ON dbo.Vacation_List      TO shiftswap_api;
GRANT EXECUTE ON dbo.Schedule_Get       TO shiftswap_api;
GRANT EXECUTE ON dbo.Schedule_GetTeam   TO shiftswap_api;
GRANT EXECUTE ON dbo.Swap_Request       TO shiftswap_api;
GRANT EXECUTE ON dbo.Swap_Approve       TO shiftswap_api;
GRANT EXECUTE ON dbo.Swap_Decline       TO shiftswap_api;
GRANT EXECUTE ON dbo.Swap_Cancel        TO shiftswap_api;
GRANT EXECUTE ON dbo.Swap_List          TO shiftswap_api;
/* Swap_GetOne and Audit_Write are internal; ownership chaining lets the public procs call them. */
GO

/* DAB reads metadata to build its schema. */
GRANT VIEW DEFINITION TO shiftswap_api;
GO
PRINT 'Security configured.';
