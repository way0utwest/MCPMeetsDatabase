/* Seed data: 3 jobs, 8 employees (2 managers), 4 weeks of shifts starting next Monday. Re-runnable. */
USE ShiftSwap;
GO
SET NOCOUNT ON;

MERGE dbo.Job AS t
USING (VALUES
    (N'Cashier',    N'Front register and customer checkout'),
    (N'Cook',       N'Kitchen line'),
    (N'Front Desk', N'Reception, phones, bookings')) AS s(Name, Description)
ON t.Name = s.Name
WHEN NOT MATCHED THEN INSERT (Name, Description) VALUES (s.Name, s.Description);

DECLARE @Cashier int = (SELECT JobId FROM dbo.Job WHERE Name = N'Cashier');
DECLARE @Cook    int = (SELECT JobId FROM dbo.Job WHERE Name = N'Cook');
DECLARE @Desk    int = (SELECT JobId FROM dbo.Job WHERE Name = N'Front Desk');

/* Managers first so reports can reference them. */
MERGE dbo.Employee AS t
USING (VALUES
    (N'maria.lopez@contoso.com',  N'Maria Lopez',  @Cashier, 1),
    (N'ken.okafor@contoso.com',   N'Ken Okafor',   @Cook,    1)) AS s(Email, DisplayName, JobId, IsManager)
ON t.Email = s.Email
WHEN NOT MATCHED THEN INSERT (Email, DisplayName, JobId, IsManager) VALUES (s.Email, s.DisplayName, s.JobId, s.IsManager);

DECLARE @Maria int = (SELECT EmployeeId FROM dbo.Employee WHERE Email = N'maria.lopez@contoso.com');
DECLARE @Ken   int = (SELECT EmployeeId FROM dbo.Employee WHERE Email = N'ken.okafor@contoso.com');

MERGE dbo.Employee AS t
USING (VALUES
    (N'alice.chen@contoso.com',   N'Alice Chen',   @Cashier, @Maria),
    (N'bob.singh@contoso.com',    N'Bob Singh',    @Cashier, @Maria),
    (N'cara.diaz@contoso.com',    N'Cara Diaz',    @Cashier, @Maria),
    (N'dave.park@contoso.com',    N'Dave Park',    @Cook,    @Ken),
    (N'erin.walsh@contoso.com',   N'Erin Walsh',   @Cook,    @Ken),
    (N'frank.moss@contoso.com',   N'Frank Moss',   @Desk,    @Maria)) AS s(Email, DisplayName, JobId, ManagerId)
ON t.Email = s.Email
WHEN NOT MATCHED THEN INSERT (Email, DisplayName, JobId, ManagerId) VALUES (s.Email, s.DisplayName, s.JobId, s.ManagerId);

/* Shifts: 4 weeks from next Monday, Mon-Sat, two cashier shifts, one cook shift, one desk shift per day.
   Rotate assignments so every employee has shifts and some are left open. */
IF NOT EXISTS (SELECT 1 FROM dbo.Shift)
BEGIN
    DECLARE @Start date = DATEADD(DAY, (8 - DATEPART(WEEKDAY, CAST(GETDATE() AS date))) % 7 + 1, CAST(GETDATE() AS date)); -- next Monday (DATEFIRST-agnostic enough for demo)
    DECLARE @d int = 0;
    WHILE @d < 28
    BEGIN
        DECLARE @Day date = DATEADD(DAY, @d, @Start);
        IF DATENAME(WEEKDAY, @Day) <> 'Sunday'
        BEGIN
            DECLARE @cashiers TABLE (rn int, EmployeeId int);
            DELETE @cashiers;
            INSERT @cashiers SELECT ROW_NUMBER() OVER (ORDER BY EmployeeId), EmployeeId FROM dbo.Employee WHERE JobId = @Cashier AND IsManager = 0;
            DECLARE @cooks TABLE (rn int, EmployeeId int);
            DELETE @cooks;
            INSERT @cooks SELECT ROW_NUMBER() OVER (ORDER BY EmployeeId), EmployeeId FROM dbo.Employee WHERE JobId = @Cook AND IsManager = 0;

            INSERT dbo.Shift (JobId, ShiftDate, StartTime, EndTime, Location, AssignedEmployeeId) VALUES
                (@Cashier, @Day, '08:00', '14:00', N'Store 1', (SELECT EmployeeId FROM @cashiers WHERE rn = (@d % 3) + 1)),
                (@Cashier, @Day, '14:00', '20:00', N'Store 1', CASE WHEN @d % 5 = 4 THEN NULL ELSE (SELECT EmployeeId FROM @cashiers WHERE rn = ((@d + 1) % 3) + 1) END),
                (@Cook,    @Day, '10:00', '18:00', N'Kitchen', (SELECT EmployeeId FROM @cooks WHERE rn = (@d % 2) + 1)),
                (@Desk,    @Day, '09:00', '17:00', N'Lobby',   (SELECT EmployeeId FROM dbo.Employee WHERE Email = N'frank.moss@contoso.com'));
        END
        SET @d += 1;
    END
END

/* One sample vacation request and one pending swap so the UI has something to show. */
IF NOT EXISTS (SELECT 1 FROM dbo.Vacation)
    INSERT dbo.Vacation (EmployeeId, StartDate, EndDate, Reason)
    SELECT EmployeeId, DATEADD(DAY, 10, CAST(GETDATE() AS date)), DATEADD(DAY, 12, CAST(GETDATE() AS date)), N'Long weekend'
    FROM dbo.Employee WHERE Email = N'alice.chen@contoso.com';

PRINT 'Seed complete.';
GO
