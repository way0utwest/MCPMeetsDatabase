/* Vacation procedures. Every proc takes the acting user's email, resolved from the auth token by the API layer. */
USE ShiftSwap;
GO

/* Request vacation for yourself. */
CREATE OR ALTER PROCEDURE dbo.Vacation_Request
    @Email     nvarchar(256),
    @StartDate date,
    @EndDate   date,
    @Reason    nvarchar(400) = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;

    DECLARE @Me int = dbo.fn_EmployeeIdFromEmail(@Email);
    IF @Me IS NULL THROW 50001, 'Unknown or inactive employee.', 1;
    IF @EndDate < @StartDate THROW 50002, 'End date must be on or after start date.', 1;
    IF @StartDate < CAST(GETDATE() AS date) THROW 50003, 'Vacation cannot start in the past.', 1;

    IF EXISTS (SELECT 1 FROM dbo.Vacation
               WHERE EmployeeId = @Me AND Status IN ('Requested','Approved')
                 AND StartDate <= @EndDate AND EndDate >= @StartDate)
        THROW 50004, 'You already have a requested or approved vacation overlapping those dates.', 1;

    DECLARE @Id TABLE (VacationId int);
    INSERT dbo.Vacation (EmployeeId, StartDate, EndDate, Reason)
    OUTPUT inserted.VacationId INTO @Id
    VALUES (@Me, @StartDate, @EndDate, @Reason);

    DECLARE @VacationId int = (SELECT VacationId FROM @Id);
    EXEC dbo.Audit_Write @Email, 'Vacation.Request', 'Vacation', @VacationId, @Reason;

    SELECT v.VacationId, v.StartDate, v.EndDate, v.Status, v.Reason, v.RequestedAt
    FROM dbo.Vacation v WHERE v.VacationId = @VacationId;
END;
GO

/* Approve or deny a direct report's request. @Approve = 1 approves, 0 denies. */
CREATE OR ALTER PROCEDURE dbo.Vacation_Approve
    @ManagerEmail nvarchar(256),
    @VacationId   int,
    @Approve      bit,
    @Notes        nvarchar(400) = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;

    DECLARE @Mgr int = dbo.fn_EmployeeIdFromEmail(@ManagerEmail);
    IF @Mgr IS NULL THROW 50001, 'Unknown or inactive employee.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Employee WHERE EmployeeId = @Mgr AND IsManager = 1)
        THROW 50010, 'Only managers can approve or deny vacation.', 1;

    DECLARE @EmpId int, @Status varchar(12), @Start date, @End date, @EmpMgr int;
    SELECT @EmpId = v.EmployeeId, @Status = v.Status, @Start = v.StartDate, @End = v.EndDate, @EmpMgr = e.ManagerId
    FROM dbo.Vacation v JOIN dbo.Employee e ON e.EmployeeId = v.EmployeeId
    WHERE v.VacationId = @VacationId;

    IF @EmpId IS NULL THROW 50011, 'Vacation request not found.', 1;
    IF @EmpMgr IS NOT NULL AND @EmpMgr <> @Mgr THROW 50012, 'You are not this employee''s manager.', 1;
    IF @Status <> 'Requested' THROW 50013, 'Only requests in Requested status can be decided.', 1;

    IF @Approve = 1 AND EXISTS (SELECT 1 FROM dbo.Vacation
                                WHERE EmployeeId = @EmpId AND Status = 'Approved' AND VacationId <> @VacationId
                                  AND StartDate <= @End AND EndDate >= @Start)
        THROW 50014, 'Employee already has approved vacation overlapping these dates.', 1;

    UPDATE dbo.Vacation
    SET Status = CASE WHEN @Approve = 1 THEN 'Approved' ELSE 'Denied' END,
        DecidedByEmployeeId = @Mgr, DecidedAt = sysutcdatetime(), DecisionNotes = @Notes
    WHERE VacationId = @VacationId;

    DECLARE @Action varchar(40) = CASE WHEN @Approve = 1 THEN 'Vacation.Approve' ELSE 'Vacation.Deny' END;
    EXEC dbo.Audit_Write @ManagerEmail, @Action, 'Vacation', @VacationId, @Notes;

    SELECT v.VacationId, e.Email AS EmployeeEmail, e.DisplayName, v.StartDate, v.EndDate, v.Status, v.DecidedAt, v.DecisionNotes
    FROM dbo.Vacation v JOIN dbo.Employee e ON e.EmployeeId = v.EmployeeId
    WHERE v.VacationId = @VacationId;
END;
GO

/* Cancel your own request, or (as the manager) a report's request. */
CREATE OR ALTER PROCEDURE dbo.Vacation_Cancel
    @Email      nvarchar(256),
    @VacationId int
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;

    DECLARE @Me int = dbo.fn_EmployeeIdFromEmail(@Email);
    IF @Me IS NULL THROW 50001, 'Unknown or inactive employee.', 1;

    DECLARE @EmpId int, @Status varchar(12), @Start date, @EmpMgr int;
    SELECT @EmpId = v.EmployeeId, @Status = v.Status, @Start = v.StartDate, @EmpMgr = e.ManagerId
    FROM dbo.Vacation v JOIN dbo.Employee e ON e.EmployeeId = v.EmployeeId
    WHERE v.VacationId = @VacationId;

    IF @EmpId IS NULL THROW 50011, 'Vacation request not found.', 1;
    IF @EmpId <> @Me AND ISNULL(@EmpMgr, -1) <> @Me THROW 50020, 'You can only cancel your own vacation or that of a direct report.', 1;
    IF @Status NOT IN ('Requested','Approved') THROW 50021, 'Only Requested or Approved vacation can be cancelled.', 1;
    IF @Start < CAST(GETDATE() AS date) THROW 50022, 'Vacation that has already started cannot be cancelled.', 1;

    UPDATE dbo.Vacation SET Status = 'Cancelled', DecidedAt = sysutcdatetime(), DecidedByEmployeeId = @Me
    WHERE VacationId = @VacationId;

    EXEC dbo.Audit_Write @Email, 'Vacation.Cancel', 'Vacation', @VacationId, NULL;

    SELECT VacationId, StartDate, EndDate, Status FROM dbo.Vacation WHERE VacationId = @VacationId;
END;
GO

/* List your vacation. Managers passing @IncludeTeam = 1 also see direct reports. */
CREATE OR ALTER PROCEDURE dbo.Vacation_List
    @Email       nvarchar(256),
    @IncludeTeam bit = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Me int = dbo.fn_EmployeeIdFromEmail(@Email);
    IF @Me IS NULL THROW 50001, 'Unknown or inactive employee.', 1;

    SELECT v.VacationId, e.Email AS EmployeeEmail, e.DisplayName, v.StartDate, v.EndDate, v.Status, v.Reason,
           v.RequestedAt, d.DisplayName AS DecidedBy, v.DecidedAt, v.DecisionNotes,
           CASE WHEN v.EmployeeId = @Me THEN 1 ELSE 0 END AS IsMine
    FROM dbo.Vacation v
    JOIN dbo.Employee e ON e.EmployeeId = v.EmployeeId
    LEFT JOIN dbo.Employee d ON d.EmployeeId = v.DecidedByEmployeeId
    WHERE v.EmployeeId = @Me
       OR (@IncludeTeam = 1 AND e.ManagerId = @Me)
    ORDER BY v.StartDate DESC;
END;
GO
