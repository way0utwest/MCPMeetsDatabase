/* Shift swap procedures. A swap completes only when both parties have approved. */
USE ShiftSwap;
GO

/* Internal: one swap with both shifts described. */
CREATE OR ALTER PROCEDURE dbo.Swap_GetOne
    @SwapId int
AS
BEGIN
    SET NOCOUNT ON;
    SELECT s.SwapId, s.Status, s.RequesterApproved, s.CounterpartyApproved, s.CreatedAt, s.CompletedAt,
           r.Email AS RequesterEmail, r.DisplayName AS RequesterName,
           rs.ShiftId AS RequesterShiftId, rs.ShiftDate AS RequesterShiftDate, rs.StartTime AS RequesterStart, rs.EndTime AS RequesterEnd,
           c.Email AS CounterpartyEmail, c.DisplayName AS CounterpartyName,
           cs.ShiftId AS CounterpartyShiftId, cs.ShiftDate AS CounterpartyShiftDate, cs.StartTime AS CounterpartyStart, cs.EndTime AS CounterpartyEnd,
           j.Name AS JobName
    FROM dbo.ShiftSwapRequest s
    JOIN dbo.Employee r  ON r.EmployeeId = s.RequesterEmployeeId
    JOIN dbo.Employee c  ON c.EmployeeId = s.CounterpartyEmployeeId
    JOIN dbo.Shift rs    ON rs.ShiftId = s.RequesterShiftId
    JOIN dbo.Shift cs    ON cs.ShiftId = s.CounterpartyShiftId
    JOIN dbo.Job j       ON j.JobId = rs.JobId
    WHERE s.SwapId = @SwapId;
END;
GO

/* Propose swapping one of your shifts for a colleague's shift (same job). Requester is auto-approved. */
CREATE OR ALTER PROCEDURE dbo.Swap_Request
    @Email        nvarchar(256),
    @MyShiftId    int,
    @TheirShiftId int
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;

    DECLARE @Me int = dbo.fn_EmployeeIdFromEmail(@Email);
    IF @Me IS NULL THROW 50001, 'Unknown or inactive employee.', 1;
    IF @MyShiftId = @TheirShiftId THROW 50030, 'Pick two different shifts.', 1;

    DECLARE @MyJob int, @MyDate date, @MyOwner int;
    SELECT @MyJob = JobId, @MyDate = ShiftDate, @MyOwner = AssignedEmployeeId FROM dbo.Shift WHERE ShiftId = @MyShiftId;
    IF @MyJob IS NULL THROW 50031, 'Your shift was not found.', 1;
    IF @MyOwner IS NULL OR @MyOwner <> @Me THROW 50032, 'That shift is not assigned to you.', 1;
    IF @MyDate < CAST(GETDATE() AS date) THROW 50033, 'Cannot swap a shift in the past.', 1;

    DECLARE @TheirJob int, @TheirDate date, @Them int;
    SELECT @TheirJob = JobId, @TheirDate = ShiftDate, @Them = AssignedEmployeeId FROM dbo.Shift WHERE ShiftId = @TheirShiftId;
    IF @TheirJob IS NULL THROW 50034, 'The other shift was not found.', 1;
    IF @Them IS NULL THROW 50035, 'The other shift is unassigned; ask a manager to assign it instead of swapping.', 1;
    IF @Them = @Me THROW 50036, 'Both shifts are already yours.', 1;
    IF @TheirDate < CAST(GETDATE() AS date) THROW 50033, 'Cannot swap a shift in the past.', 1;
    IF @TheirJob <> @MyJob THROW 50037, 'Shifts must be for the same job.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Employee WHERE EmployeeId = @Them AND IsActive = 1 AND JobId = @MyJob)
        THROW 50038, 'The other employee is not active in this job.', 1;

    IF EXISTS (SELECT 1 FROM dbo.ShiftSwapRequest
               WHERE Status = 'Pending'
                 AND (RequesterShiftId IN (@MyShiftId, @TheirShiftId) OR CounterpartyShiftId IN (@MyShiftId, @TheirShiftId)))
        THROW 50039, 'One of these shifts is already in a pending swap.', 1;

    DECLARE @Id TABLE (SwapId int);
    INSERT dbo.ShiftSwapRequest (RequesterEmployeeId, RequesterShiftId, CounterpartyEmployeeId, CounterpartyShiftId)
    OUTPUT inserted.SwapId INTO @Id
    VALUES (@Me, @MyShiftId, @Them, @TheirShiftId);

    DECLARE @SwapId int = (SELECT SwapId FROM @Id);
    DECLARE @Detail nvarchar(1000) = CONCAT('MyShift=', @MyShiftId, ' TheirShift=', @TheirShiftId);
    EXEC dbo.Audit_Write @Email, 'Swap.Request', 'ShiftSwapRequest', @SwapId, @Detail;

    EXEC dbo.Swap_GetOne @SwapId;
END;
GO


/* Approve a pending swap you are part of. When both have approved, the shifts exchange owners atomically. */
CREATE OR ALTER PROCEDURE dbo.Swap_Approve
    @Email  nvarchar(256),
    @SwapId int
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;

    DECLARE @Me int = dbo.fn_EmployeeIdFromEmail(@Email);
    IF @Me IS NULL THROW 50001, 'Unknown or inactive employee.', 1;

    BEGIN TRAN;

    DECLARE @Req int, @Cp int, @ReqShift int, @CpShift int, @Status varchar(12), @ReqOk bit, @CpOk bit;
    SELECT @Req = RequesterEmployeeId, @Cp = CounterpartyEmployeeId, @ReqShift = RequesterShiftId, @CpShift = CounterpartyShiftId,
           @Status = Status, @ReqOk = RequesterApproved, @CpOk = CounterpartyApproved
    FROM dbo.ShiftSwapRequest WITH (UPDLOCK, HOLDLOCK)
    WHERE SwapId = @SwapId;

    IF @Req IS NULL THROW 50040, 'Swap request not found.', 1;
    IF @Status <> 'Pending' THROW 50041, 'This swap is no longer pending.', 1;
    IF @Me NOT IN (@Req, @Cp) THROW 50042, 'You are not part of this swap.', 1;

    IF @Me = @Req SET @ReqOk = 1; ELSE SET @CpOk = 1;

    UPDATE dbo.ShiftSwapRequest SET RequesterApproved = @ReqOk, CounterpartyApproved = @CpOk WHERE SwapId = @SwapId;
    EXEC dbo.Audit_Write @Email, 'Swap.Approve', 'ShiftSwapRequest', @SwapId, NULL;

    IF @ReqOk = 1 AND @CpOk = 1
    BEGIN
        /* Re-check ownership under lock: both shifts must still belong to the original parties. */
        IF NOT EXISTS (SELECT 1 FROM dbo.Shift WITH (UPDLOCK, HOLDLOCK) WHERE ShiftId = @ReqShift AND AssignedEmployeeId = @Req)
           OR NOT EXISTS (SELECT 1 FROM dbo.Shift WITH (UPDLOCK, HOLDLOCK) WHERE ShiftId = @CpShift AND AssignedEmployeeId = @Cp)
        BEGIN
            UPDATE dbo.ShiftSwapRequest SET Status = 'Cancelled', CompletedAt = sysutcdatetime() WHERE SwapId = @SwapId;
            EXEC dbo.Audit_Write @Email, 'Swap.AutoCancel', 'ShiftSwapRequest', @SwapId, N'Shift ownership changed before completion';
            COMMIT;
            THROW 50043, 'A shift changed hands before the swap completed; the swap was cancelled.', 1;
        END

        UPDATE dbo.Shift SET AssignedEmployeeId = @Cp  WHERE ShiftId = @ReqShift;
        UPDATE dbo.Shift SET AssignedEmployeeId = @Req WHERE ShiftId = @CpShift;
        UPDATE dbo.ShiftSwapRequest SET Status = 'Completed', CompletedAt = sysutcdatetime() WHERE SwapId = @SwapId;

        DECLARE @Detail nvarchar(1000) = CONCAT('Shift ', @ReqShift, ' -> employee ', @Cp, '; shift ', @CpShift, ' -> employee ', @Req);
        EXEC dbo.Audit_Write @Email, 'Swap.Complete', 'ShiftSwapRequest', @SwapId, @Detail;
    END

    COMMIT;
    EXEC dbo.Swap_GetOne @SwapId;
END;
GO

/* Counterparty declines. */
CREATE OR ALTER PROCEDURE dbo.Swap_Decline
    @Email  nvarchar(256),
    @SwapId int
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @Me int = dbo.fn_EmployeeIdFromEmail(@Email);
    IF @Me IS NULL THROW 50001, 'Unknown or inactive employee.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.ShiftSwapRequest WHERE SwapId = @SwapId) THROW 50040, 'Swap request not found.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.ShiftSwapRequest WHERE SwapId = @SwapId AND Status = 'Pending') THROW 50041, 'This swap is no longer pending.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.ShiftSwapRequest WHERE SwapId = @SwapId AND CounterpartyEmployeeId = @Me)
        THROW 50044, 'Only the employee being asked can decline. Requesters should cancel instead.', 1;

    UPDATE dbo.ShiftSwapRequest SET Status = 'Declined', CompletedAt = sysutcdatetime() WHERE SwapId = @SwapId;
    EXEC dbo.Audit_Write @Email, 'Swap.Decline', 'ShiftSwapRequest', @SwapId, NULL;
    EXEC dbo.Swap_GetOne @SwapId;
END;
GO

/* Requester cancels. */
CREATE OR ALTER PROCEDURE dbo.Swap_Cancel
    @Email  nvarchar(256),
    @SwapId int
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @Me int = dbo.fn_EmployeeIdFromEmail(@Email);
    IF @Me IS NULL THROW 50001, 'Unknown or inactive employee.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.ShiftSwapRequest WHERE SwapId = @SwapId) THROW 50040, 'Swap request not found.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.ShiftSwapRequest WHERE SwapId = @SwapId AND Status = 'Pending') THROW 50041, 'This swap is no longer pending.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.ShiftSwapRequest WHERE SwapId = @SwapId AND RequesterEmployeeId = @Me)
        THROW 50045, 'Only the requester can cancel. Counterparties should decline instead.', 1;

    UPDATE dbo.ShiftSwapRequest SET Status = 'Cancelled', CompletedAt = sysutcdatetime() WHERE SwapId = @SwapId;
    EXEC dbo.Audit_Write @Email, 'Swap.Cancel', 'ShiftSwapRequest', @SwapId, NULL;
    EXEC dbo.Swap_GetOne @SwapId;
END;
GO

/* All swaps you are part of, newest first. */
CREATE OR ALTER PROCEDURE dbo.Swap_List
    @Email nvarchar(256)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Me int = dbo.fn_EmployeeIdFromEmail(@Email);
    IF @Me IS NULL THROW 50001, 'Unknown or inactive employee.', 1;

    SELECT s.SwapId, s.Status, s.RequesterApproved, s.CounterpartyApproved, s.CreatedAt, s.CompletedAt,
           CASE WHEN s.RequesterEmployeeId = @Me THEN 'Requester' ELSE 'Counterparty' END AS MyRole,
           r.Email AS RequesterEmail, r.DisplayName AS RequesterName,
           rs.ShiftId AS RequesterShiftId, rs.ShiftDate AS RequesterShiftDate, rs.StartTime AS RequesterStart, rs.EndTime AS RequesterEnd,
           c.Email AS CounterpartyEmail, c.DisplayName AS CounterpartyName,
           cs.ShiftId AS CounterpartyShiftId, cs.ShiftDate AS CounterpartyShiftDate, cs.StartTime AS CounterpartyStart, cs.EndTime AS CounterpartyEnd,
           j.Name AS JobName
    FROM dbo.ShiftSwapRequest s
    JOIN dbo.Employee r ON r.EmployeeId = s.RequesterEmployeeId
    JOIN dbo.Employee c ON c.EmployeeId = s.CounterpartyEmployeeId
    JOIN dbo.Shift rs   ON rs.ShiftId = s.RequesterShiftId
    JOIN dbo.Shift cs   ON cs.ShiftId = s.CounterpartyShiftId
    JOIN dbo.Job j      ON j.JobId = rs.JobId
    WHERE @Me IN (s.RequesterEmployeeId, s.CounterpartyEmployeeId)
    ORDER BY s.CreatedAt DESC;
END;
GO
