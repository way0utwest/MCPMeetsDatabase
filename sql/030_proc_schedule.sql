/* Schedule read procedures. */
USE ShiftSwap;
GO

/* Your assigned shifts in a date range. Defaults to the next 14 days. */
CREATE OR ALTER PROCEDURE dbo.Schedule_Get
    @Email    nvarchar(256),
    @FromDate date = NULL,
    @ToDate   date = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Me int = dbo.fn_EmployeeIdFromEmail(@Email);
    IF @Me IS NULL THROW 50001, 'Unknown or inactive employee.', 1;

    SET @FromDate = ISNULL(@FromDate, CAST(GETDATE() AS date));
    SET @ToDate   = ISNULL(@ToDate, DATEADD(DAY, 14, @FromDate));

    SELECT s.ShiftId, s.ShiftDate, DATENAME(WEEKDAY, s.ShiftDate) AS DayName, s.StartTime, s.EndTime, s.Location,
           j.JobId, j.Name AS JobName,
           CASE WHEN EXISTS (SELECT 1 FROM dbo.ShiftSwapRequest x
                             WHERE x.Status = 'Pending' AND (x.RequesterShiftId = s.ShiftId OR x.CounterpartyShiftId = s.ShiftId))
                THEN 1 ELSE 0 END AS InPendingSwap
    FROM dbo.Shift s
    JOIN dbo.Job j ON j.JobId = s.JobId
    WHERE s.AssignedEmployeeId = @Me
      AND s.ShiftDate BETWEEN @FromDate AND @ToDate
    ORDER BY s.ShiftDate, s.StartTime;
END;
GO

/* Everyone's shifts for your job in a date range, including open shifts. Use it to find a swap partner. */
CREATE OR ALTER PROCEDURE dbo.Schedule_GetTeam
    @Email    nvarchar(256),
    @FromDate date = NULL,
    @ToDate   date = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Me int = dbo.fn_EmployeeIdFromEmail(@Email);
    IF @Me IS NULL THROW 50001, 'Unknown or inactive employee.', 1;

    DECLARE @MyJob int = (SELECT JobId FROM dbo.Employee WHERE EmployeeId = @Me);
    SET @FromDate = ISNULL(@FromDate, CAST(GETDATE() AS date));
    SET @ToDate   = ISNULL(@ToDate, DATEADD(DAY, 14, @FromDate));

    SELECT s.ShiftId, s.ShiftDate, DATENAME(WEEKDAY, s.ShiftDate) AS DayName, s.StartTime, s.EndTime, s.Location,
           j.Name AS JobName,
           e.Email AS AssignedEmail, e.DisplayName AS AssignedName,
           CASE WHEN s.AssignedEmployeeId IS NULL THEN 1 ELSE 0 END AS IsOpen,
           CASE WHEN s.AssignedEmployeeId = @Me THEN 1 ELSE 0 END AS IsMine,
           CASE WHEN EXISTS (SELECT 1 FROM dbo.ShiftSwapRequest x
                             WHERE x.Status = 'Pending' AND (x.RequesterShiftId = s.ShiftId OR x.CounterpartyShiftId = s.ShiftId))
                THEN 1 ELSE 0 END AS InPendingSwap
    FROM dbo.Shift s
    JOIN dbo.Job j ON j.JobId = s.JobId
    LEFT JOIN dbo.Employee e ON e.EmployeeId = s.AssignedEmployeeId
    WHERE s.JobId = @MyJob
      AND s.ShiftDate BETWEEN @FromDate AND @ToDate
    ORDER BY s.ShiftDate, s.StartTime, e.DisplayName;
END;
GO
