/* ShiftSwap schema. Run first. Idempotent. */
IF DB_ID(N'ShiftSwap') IS NULL
    CREATE DATABASE ShiftSwap;
GO
USE ShiftSwap;
GO

IF OBJECT_ID(N'dbo.Job') IS NULL
CREATE TABLE dbo.Job
(
    JobId        int           IDENTITY(1,1) NOT NULL CONSTRAINT PK_Job PRIMARY KEY,
    Name         nvarchar(60)  NOT NULL CONSTRAINT UQ_Job_Name UNIQUE,
    Description  nvarchar(200) NULL
);
GO

IF OBJECT_ID(N'dbo.Employee') IS NULL
CREATE TABLE dbo.Employee
(
    EmployeeId   int            IDENTITY(1,1) NOT NULL CONSTRAINT PK_Employee PRIMARY KEY,
    Email        nvarchar(256)  NOT NULL CONSTRAINT UQ_Employee_Email UNIQUE,
    DisplayName  nvarchar(120)  NOT NULL,
    JobId        int            NOT NULL CONSTRAINT FK_Employee_Job REFERENCES dbo.Job(JobId),
    ManagerId    int            NULL     CONSTRAINT FK_Employee_Manager REFERENCES dbo.Employee(EmployeeId),
    IsManager    bit            NOT NULL CONSTRAINT DF_Employee_IsManager DEFAULT (0),
    IsActive     bit            NOT NULL CONSTRAINT DF_Employee_IsActive DEFAULT (1),
    CreatedAt    datetime2(0)   NOT NULL CONSTRAINT DF_Employee_CreatedAt DEFAULT (sysutcdatetime())
);
GO

IF OBJECT_ID(N'dbo.Shift') IS NULL
CREATE TABLE dbo.Shift
(
    ShiftId             int          IDENTITY(1,1) NOT NULL CONSTRAINT PK_Shift PRIMARY KEY,
    JobId               int          NOT NULL CONSTRAINT FK_Shift_Job REFERENCES dbo.Job(JobId),
    ShiftDate           date         NOT NULL,
    StartTime           time(0)      NOT NULL,
    EndTime             time(0)      NOT NULL,
    Location            nvarchar(80) NULL,
    AssignedEmployeeId  int          NULL CONSTRAINT FK_Shift_Employee REFERENCES dbo.Employee(EmployeeId),
    CONSTRAINT CK_Shift_Times CHECK (EndTime > StartTime)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Shift_Employee_Date' AND object_id = OBJECT_ID(N'dbo.Shift'))
    CREATE INDEX IX_Shift_Employee_Date ON dbo.Shift (AssignedEmployeeId, ShiftDate) INCLUDE (JobId, StartTime, EndTime);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Shift_Job_Date' AND object_id = OBJECT_ID(N'dbo.Shift'))
    CREATE INDEX IX_Shift_Job_Date ON dbo.Shift (JobId, ShiftDate);
GO

IF OBJECT_ID(N'dbo.Vacation') IS NULL
CREATE TABLE dbo.Vacation
(
    VacationId            int           IDENTITY(1,1) NOT NULL CONSTRAINT PK_Vacation PRIMARY KEY,
    EmployeeId            int           NOT NULL CONSTRAINT FK_Vacation_Employee REFERENCES dbo.Employee(EmployeeId),
    StartDate             date          NOT NULL,
    EndDate               date          NOT NULL,
    Status                varchar(12)   NOT NULL CONSTRAINT DF_Vacation_Status DEFAULT ('Requested'),
    Reason                nvarchar(400) NULL,
    RequestedAt           datetime2(0)  NOT NULL CONSTRAINT DF_Vacation_RequestedAt DEFAULT (sysutcdatetime()),
    DecidedByEmployeeId   int           NULL CONSTRAINT FK_Vacation_DecidedBy REFERENCES dbo.Employee(EmployeeId),
    DecidedAt             datetime2(0)  NULL,
    DecisionNotes         nvarchar(400) NULL,
    CONSTRAINT CK_Vacation_Dates  CHECK (EndDate >= StartDate),
    CONSTRAINT CK_Vacation_Status CHECK (Status IN ('Requested','Approved','Denied','Cancelled'))
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Vacation_Employee' AND object_id = OBJECT_ID(N'dbo.Vacation'))
    CREATE INDEX IX_Vacation_Employee ON dbo.Vacation (EmployeeId, Status, StartDate);
GO

IF OBJECT_ID(N'dbo.ShiftSwapRequest') IS NULL
CREATE TABLE dbo.ShiftSwapRequest
(
    SwapId                  int          IDENTITY(1,1) NOT NULL CONSTRAINT PK_ShiftSwapRequest PRIMARY KEY,
    RequesterEmployeeId     int          NOT NULL CONSTRAINT FK_Swap_Requester   REFERENCES dbo.Employee(EmployeeId),
    RequesterShiftId        int          NOT NULL CONSTRAINT FK_Swap_ReqShift    REFERENCES dbo.Shift(ShiftId),
    CounterpartyEmployeeId  int          NOT NULL CONSTRAINT FK_Swap_Counterparty REFERENCES dbo.Employee(EmployeeId),
    CounterpartyShiftId     int          NOT NULL CONSTRAINT FK_Swap_CpShift     REFERENCES dbo.Shift(ShiftId),
    RequesterApproved       bit          NOT NULL CONSTRAINT DF_Swap_ReqApproved DEFAULT (1),
    CounterpartyApproved    bit          NOT NULL CONSTRAINT DF_Swap_CpApproved  DEFAULT (0),
    Status                  varchar(12)  NOT NULL CONSTRAINT DF_Swap_Status DEFAULT ('Pending'),
    CreatedAt               datetime2(0) NOT NULL CONSTRAINT DF_Swap_CreatedAt DEFAULT (sysutcdatetime()),
    CompletedAt             datetime2(0) NULL,
    CONSTRAINT CK_Swap_Status  CHECK (Status IN ('Pending','Completed','Declined','Cancelled')),
    CONSTRAINT CK_Swap_Distinct CHECK (RequesterShiftId <> CounterpartyShiftId AND RequesterEmployeeId <> CounterpartyEmployeeId)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Swap_Pending_Shifts' AND object_id = OBJECT_ID(N'dbo.ShiftSwapRequest'))
    CREATE INDEX IX_Swap_Pending_Shifts ON dbo.ShiftSwapRequest (Status, RequesterShiftId, CounterpartyShiftId);
GO

IF OBJECT_ID(N'dbo.AuditLog') IS NULL
CREATE TABLE dbo.AuditLog
(
    AuditId     bigint         IDENTITY(1,1) NOT NULL CONSTRAINT PK_AuditLog PRIMARY KEY,
    OccurredAt  datetime2(0)   NOT NULL CONSTRAINT DF_AuditLog_OccurredAt DEFAULT (sysutcdatetime()),
    ActorEmail  nvarchar(256)  NOT NULL,
    Action      varchar(40)    NOT NULL,
    EntityType  varchar(30)    NOT NULL,
    EntityId    int            NULL,
    Detail      nvarchar(1000) NULL
);
GO

/* Helper: resolve an email to an active employee id or throw. Used by every procedure. */
CREATE OR ALTER FUNCTION dbo.fn_EmployeeIdFromEmail (@Email nvarchar(256))
RETURNS int
AS
BEGIN
    RETURN (SELECT EmployeeId FROM dbo.Employee WHERE Email = @Email AND IsActive = 1);
END;
GO

CREATE OR ALTER PROCEDURE dbo.Audit_Write
    @ActorEmail nvarchar(256),
    @Action     varchar(40),
    @EntityType varchar(30),
    @EntityId   int = NULL,
    @Detail     nvarchar(1000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT dbo.AuditLog (ActorEmail, Action, EntityType, EntityId, Detail)
    VALUES (@ActorEmail, @Action, @EntityType, @EntityId, @Detail);
END;
GO
