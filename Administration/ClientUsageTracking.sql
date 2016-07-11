/*

Track Historian Client Usage
============================

This SQL script extends the Historian "Runtime" database by adding several database objects
to track Historian Client usage. It makes no changes to standard "Runtime" objects, apart 
from some standard configuration changes. This utility requires SQLAgent to be running.

The usage tracking is reported through:

	.	Some new "tags" that reflect the count of users/nodes using the system. The
		values for these tags are set by a SQL Agent job (wwkbUsageActiveUsers, 
		wwkbUsageActiveNodes, wwkbUsageConnectedUsers, wwkbUsageConnectedNodes).

	.	A table listing the currently connected sessions (wwkbUsageActive)

	.	A table summarizing the connection information on a daily basis (wwkbUsageSummary)

For all of these, "current" and "active" connections are both counted, with "active" included 
in "current". "Active" reflect connections which have executed a query in the last minute.

*/
use Runtime
GO


/*
   -------------------------------------------------------------------------------------------
   Create the "wwkbUsageActive" table if it does not already exist. This tracks connections
   that have been open since sometime since the last time the stored procedure
   "wwkbUsageRefreshSummary" was last executed (as provided, that occurs daily). This table is
   updated by the stored procedure "wwkbUsageRefreshActive" (as provided, that occurs each minute)
   -------------------------------------------------------------------------------------------
*/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[wwkbUsageActive]') AND type in (N'U'))
BEGIN
CREATE TABLE [dbo].[wwkbUsageActive](
	[Node] [nvarchar](200) NOT NULL,
	[UserName] [nvarchar](200) NOT NULL,
	[CID] [uniqueidentifier] NOT NULL CONSTRAINT [DF_wwkbUsageActive_CID]  DEFAULT ('00000000-0000-0000-0000-000000000000'),
	[PID] [int] NULL,
	[MACAddress] [nvarchar](20) NULL,
	[IPAddress] [nvarchar](50) NULL,
	[LastTime] [datetime] NOT NULL CONSTRAINT [DF_wwkbUsageActive_LastTime]  DEFAULT (getdate()),
	[FirstTime] [datetime] NOT NULL CONSTRAINT [DF_wwkbUsageActive_FirstTime]  DEFAULT (getdate()),
	[Application] [nvarchar](50) NOT NULL,
	[CPUUsage] [bigint] NOT NULL CONSTRAINT [DF_wwkbUsageActive_CPUUsage]  DEFAULT ((0)),
	[MemUsage] [bigint] NOT NULL CONSTRAINT [DF_wwkbUsageActive_MemUsage]  DEFAULT ((0)),
	[IOUsage] [bigint] NOT NULL CONSTRAINT [DF_wwkbUsageActive_IOUsage]  DEFAULT ((0)),
 CONSTRAINT [PK_wwkbUsageActive] PRIMARY KEY CLUSTERED 
(
	[Node] ASC,
	[UserName] ASC,
	[CID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
END
GO

/*
   -------------------------------------------------------------------------------------------
   Create the "wwkbUsageSummary" table if it does not already exist. This records the long-term
   usage history for connections. It is updated by the stored procedure "wwkbUsageRefreshSummary"
   was last executed (as provided, that occurs daily) and only reflects closed connections.
   -------------------------------------------------------------------------------------------
*/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[wwkbUsageSummary]') AND type in (N'U'))
BEGIN
CREATE TABLE [dbo].[wwkbUsageSummary](
	[UsageType] [nvarchar](25) NOT NULL,
	[Name] [nvarchar](200) NOT NULL,
	[FirstTime] [datetime] NOT NULL,
	[LastTime] [datetime] NOT NULL,
	[ActiveDays] [int] NOT NULL CONSTRAINT [DF_wwkbUsageSummary_ActiveDays]  DEFAULT ((0)),
	[Usage] [bigint] NOT NULL CONSTRAINT [DF_wwkbUsageSummary_CPUUsage]  DEFAULT ((0)),
 CONSTRAINT [PK_wwkbUsageSummary] PRIMARY KEY CLUSTERED 
(
	[UsageType] ASC,
	[Name] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
END
GO

/*
   -------------------------------------------------------------------------------------------
   Create the "wwkbUsageCurrentProcesses" view to simplify gathering information about the
   currently open connections
   -------------------------------------------------------------------------------------------
*/
IF EXISTS (SELECT * FROM sys.views WHERE object_id = OBJECT_ID(N'[dbo].[wwkbUsageCurrentProcesses]'))
	DROP VIEW [dbo].[wwkbUsageCurrentProcesses]
GO
CREATE VIEW  [dbo].[wwkbUsageCurrentProcesses] as
select p.hostname as Node
	,a.CID as ActiveCID
	,c.connection_id as CID
	,p.hostprocess as PID
	,p.loginame as UserName
	,[program_name] as Application
	,p.net_address as MACAddress
	,c.client_net_address as IPAddress
	--,case when p.last_batch > a.LastTime then p.last_batch LastTime
	,p.login_time as FirstTime
	,p.last_batch as LastTime
	,p.cpu as CPUUsage
	,p.physical_io as IOUsage
	,p.memusage as MemUsage
--	,*
	from master.dbo.sysprocesses p with (nolock)
	join master.sys.dm_exec_connections c  with (nolock)
		on c.session_id=p.spid
		and parent_connection_id is null
	full outer join dbo.wwkbUsageActive a 
		on a.UserName=p.loginame
		and a.Node=p.hostname
		and a.CID=c.connection_id
		and a.Application=p.[program_name]
		--and a.FirstTime = p.FirstTime
	where (
		DB_NAME(dbid)='Runtime'
		and hostprocess <> ''
		and ([program_name] like 'ActiveFactory%'
			or [program_name] like 'Wonderware Historian Client%')
	) or (dbid is null and hostprocess is null)
GO

/*
   -------------------------------------------------------------------------------------------
   Create the "wwkbUsageRefreshActive" stored procedure
   -------------------------------------------------------------------------------------------
*/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[wwkbUsageRefreshActive]') AND type in (N'P', N'PC'))
BEGIN
EXEC dbo.sp_executesql @statement = N'CREATE PROCEDURE [dbo].[wwkbUsageRefreshActive] AS' 
END
GO
ALTER procedure [dbo].[wwkbUsageRefreshActive]
--with execute as 'aaAdmin' 
as
begin 
set nocount on

--execute as caller
-- This should match the rate the SP is executed
set nocount on
declare @RateSecs int
set @RateSecs = 60

-- Update existing records in the usage tracking table
update t 
set t.LastTime = a.LastTime,
	t.CPUUsage = a.CPUUsage,
	t.MemUsage = a.MemUsage,
	t.IOUsage = a.IOUsage
from dbo.wwkbUsageActive t
inner join dbo.wwkbUsageCurrentProcesses a
	on a.CID=t.CID
	and a.Node=t.Node
	and a.UserName=t.UserName
	and a.Application=t.Application
	and a.PID=t.PID
where ActiveCID is not null and a.CID is not null

-- Add new records to the usage tracking table
insert into dbo.wwkbUsageActive (Node, UserName, CID, PID, MACAddress, IPAddress, LastTime, FirstTime, Application, CPUUsage, MemUsage, IOUsage)
	select Node, UserName, CID, PID, MACAddress, IPAddress, LastTime, FirstTime, Application, CPUUsage, MemUsage, IOUsage
	from dbo.wwkbUsageCurrentProcesses
	where ActiveCID is null and CID is not null
--execute as caller;
--revert

-- Calculate "usage tag" values
declare @Tags table (TagName nvarchar(50), Value float)
insert @Tags Values( 'wwkbUsageActiveUsers', (select count(distinct UserName) from dbo.wwkbUsageActive where datediff(second,LastTime,getdate())<@RateSecs) )
insert @Tags Values( 'wwkbUsageActiveNodes', (select count(distinct IPAddress) from dbo.wwkbUsageActive where datediff(second,LastTime,getdate())<@RateSecs) )
insert @Tags Values( 'wwkbUsageConnectedUsers', (select count(distinct UserName) from dbo.wwkbUsageActive) )
insert @Tags Values( 'wwkbUsageConnectedNodes', (select count(distinct IPAddress) from dbo.wwkbUsageActive) )

-- Get a "round" time
declare @RefTime datetime2
set @RefTime='2015-01-01'
declare @Time datetime2
set @Time = dateadd(second, datediff(second,@RefTime,getdate()) / @RateSecs * @RateSecs,@RefTime) 

--revert
--execute as aaAdmin
-- Write values to History for the "usage tags"
insert dbo.History(DateTime, TagName, Value, OPCQuality, wwVersion)
	select @Time, TagName, Value, 192, 'realtime' from @Tags
end
GO


/*
   -------------------------------------------------------------------------------------------
   Create the "wwkbUsageRefreshSummary" stored procedure
   -------------------------------------------------------------------------------------------
*/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[wwkbUsageRefreshSummary]') AND type in (N'P', N'PC'))
BEGIN
EXEC dbo.sp_executesql @statement = N'CREATE PROCEDURE [dbo].[wwkbUsageRefreshSummary] AS' 
END
GO

ALTER procedure [dbo].[wwkbUsageRefreshSummary] as
begin
set nocount on

-- This should match the rate the SP is executed
declare @RateMins int
set @RateMins = 1440

declare @Usage table (UsageType varchar(25), Name nvarchar(200), FirstTime datetime, LastTime datetime, Usage bigint)

insert @Usage
select 'Node', Node
	,min(FirstTime) as FirstTime
	,max(LastTime) as LastTime
	,sum(CPUUsage+MemUsage+IOUsage) as Usage
from dbo.wwkbUsageActive
where CID in (select ActiveCID from dbo.wwkbUsageCurrentProcesses where CID is null)
group by Node

insert @Usage
select 'User', UserName
	,min(FirstTime) as FirstTime
	,max(LastTime) as LastTime
	,sum(CPUUsage+MemUsage+IOUsage) as Usage
from dbo.wwkbUsageActive
where CID in (select ActiveCID from dbo.wwkbUsageCurrentProcesses where CID is null)
group by UserName

insert @Usage 
select 'Application', Application
	,min(FirstTime) as FirstTime
	,max(LastTime) as LastTime
	,sum(CPUUsage+MemUsage+IOUsage) as Usage
from dbo.wwkbUsageActive
where CID in (select ActiveCID from dbo.wwkbUsageCurrentProcesses where CID is null)
group by Application

insert @Usage
select 'Address', IPAddress
	,min(FirstTime) as FirstTime
	,max(LastTime) as LastTime
	,sum(CPUUsage+MemUsage+IOUsage) as Usage
from dbo.wwkbUsageActive
where CID in (select ActiveCID from dbo.wwkbUsageCurrentProcesses where CID is null)
group by IPAddress

insert @Usage
select 'MACAddress', MACAddress
	,min(FirstTime) as FirstTime
	,max(LastTime) as LastTime
	,sum(CPUUsage+MemUsage+IOUsage) as Usage
from dbo.wwkbUsageActive
where CID in (select ActiveCID from dbo.wwkbUsageCurrentProcesses where CID is null)
group by MACAddress

-- Delete inactive records
delete dbo.wwkbUsageActive
where CID in (select ActiveCID from dbo.wwkbUsageCurrentProcesses where CID is null)

-- Update existing records in the usage tracking table
update t 
set 
	t.Usage = a.Usage,
	t.LastTime = a.LastTime,
	t.ActiveDays = t.ActiveDays + case 
		when t.LastTime >= a.FirstTime then 0
		when datediff(minute,t.LastTime,a.LastTime) > @RateMins then 1 
		else 0 end
from dbo.wwkbUsageSummary t
inner join @Usage a
	on t.UsageType = a.UsageType
	and t.Name = a.Name
where a.Name is not null 

-- Add new records to the usage tracking table
insert into dbo.wwkbUsageSummary (UsageType, Name, FirstTime, LastTime, Usage, ActiveDays)
select u.UsageType, u.Name, u.FirstTime, u.LastTime, u.Usage, 1
from @Usage u
left outer join dbo.wwkbUsageSummary s
	on u.UsageType = s.UsageType
	and s.Name = s.Name
where s.Name is null 

-- Purge job history for the detail data
declare @yesterday datetime
set @yesterday = dateadd(hour,-1,getdate())
exec msdb.dbo.sp_purge_jobhistory @job_name=N'WWKB-Refresh Historian Client Usage Data', @oldest_date=@yesterday

end
GO

/*
   -------------------------------------------------------------------------------------------
   Set up the proper permissions on objects
   -------------------------------------------------------------------------------------------
*/
grant select on dbo.wwkbUsageCurrentProcesses to aaAdministrators
grant select, insert, update, delete on dbo.wwkbUsageActive to aaAdministrators
grant select, insert, update, delete on dbo.wwkbUsageSummary to aaAdministrators
grant exec on dbo.wwkbUsageRefreshActive to aaAdministrators
grant exec on dbo.wwkbUsageRefreshSummary to aaAdministrators


/*
   -------------------------------------------------------------------------------------------
   Create the monitoring tags that are updated each minute
   -------------------------------------------------------------------------------------------
*/
exec aaEngineeringUnitInsert 'PerMin' 
go 
set nocount on
if not exists (select * from Tag where TagName like 'wwkbUsage%')
begin
	declare @EU int
	set @EU = (select top 1 EUKey from EngineeringUnit where Unit='PerMin') 
	if exists(select * from sys.tables t inner join sys.columns c on c.OBJECT_ID = t.OBJECT_ID where t.name='Tag' and c.name='AIHistory')
		begin  -- For Historian 11.0+
			print 'Adding tags for Historian 11.0 and later...'
			exec [dbo].[aaAnalogTagInsert] @TagName='wwkbUsageActiveUsers', @Description='Number of active user accounts in the last minute', @AcquisitionType=2, @StorageType=3,@StorageRate=0, @CreatedBy='wwkbUsage',
				@CurrentEditor=0,@EUKey=@EU,@MinEU=0,@MaxEU=100,@Scaling=0,@RawType=3,@StorageNodeKey=1,@InterpolationType=254,@AITag=0,@AIHistory=0,@IntegerSize=32,@SignedInteger=0 
			exec [dbo].[aaAnalogTagInsert] @TagName='wwkbUsageActiveNodes', @Description='Number of active client nodes in the last minute', @AcquisitionType=2, @StorageType=3,@StorageRate=0, @CreatedBy='wwkbUsage',
				@CurrentEditor=0,@EUKey=@EU,@MinEU=0,@MaxEU=100,@Scaling=0,@RawType=3,@StorageNodeKey=1,@InterpolationType=254,@AITag=0,@AIHistory=0,@IntegerSize=32,@SignedInteger=0 
			exec [dbo].[aaAnalogTagInsert] @TagName='wwkbUsageConnectedUsers', @Description='Number of user accounts with open connections in the last minute', @AcquisitionType=2, @StorageType=3,@StorageRate=0, @CreatedBy='wwkbUsage',
				@CurrentEditor=0,@EUKey=@EU,@MinEU=0,@MaxEU=100,@Scaling=0,@RawType=3,@StorageNodeKey=1,@InterpolationType=254,@AITag=0,@AIHistory=0,@IntegerSize=32,@SignedInteger=0 
			exec [dbo].[aaAnalogTagInsert] @TagName='wwkbUsageConnectedNodes', @Description='Number of client nodes with open connections in the last minute', @AcquisitionType=2, @StorageType=3,@StorageRate=0, @CreatedBy='wwkbUsage',
				@CurrentEditor=0,@EUKey=@EU,@MinEU=0,@MaxEU=100,@Scaling=0,@RawType=3,@StorageNodeKey=1,@InterpolationType=254,@AITag=0,@AIHistory=0,@IntegerSize=32,@SignedInteger=0 
		end
	else
		begin -- For Historian 10.0 and earlier
			print 'Adding tags for Historian 10.0...'
			exec [dbo].[aaAnalogTagInsert] @TagName='wwkbUsageActiveUsers', @Description='Number of active user accounts in the last minute', @AcquisitionType=2, @StorageType=3,@StorageRate=0, @CreatedBy='wwkbUsage',
				@CurrentEditor=0,@EUKey=@EU,@MinEU=0,@MaxEU=100,@Scaling=0,@RawType=3,@StorageNodeKey=1,@InterpolationType=254,@IntegerSize=32,@SignedInteger=0 
			exec [dbo].[aaAnalogTagInsert] @TagName='wwkbUsageActiveNodes', @Description='Number of active client nodes in the last minute', @AcquisitionType=2, @StorageType=3,@StorageRate=0, @CreatedBy='wwkbUsage',
				@CurrentEditor=0,@EUKey=@EU,@MinEU=0,@MaxEU=100,@Scaling=0,@RawType=3,@StorageNodeKey=1,@InterpolationType=254,@IntegerSize=32,@SignedInteger=0 
			exec [dbo].[aaAnalogTagInsert] @TagName='wwkbUsageConnectedUsers', @Description='Number of user accounts with open connections in the last minute', @AcquisitionType=2, @StorageType=3,@StorageRate=0, @CreatedBy='wwkbUsage',
				@CurrentEditor=0,@EUKey=@EU,@MinEU=0,@MaxEU=100,@Scaling=0,@RawType=3,@StorageNodeKey=1,@InterpolationType=254,@IntegerSize=32,@SignedInteger=0 
			exec [dbo].[aaAnalogTagInsert] @TagName='wwkbUsageConnectedNodes', @Description='Number of client nodes with open connections in the last minute', @AcquisitionType=2, @StorageType=3,@StorageRate=0, @CreatedBy='wwkbUsage',
				@CurrentEditor=0,@EUKey=@EU,@MinEU=0,@MaxEU=100,@Scaling=0,@RawType=3,@StorageNodeKey=1,@InterpolationType=254,@IntegerSize=32,@SignedInteger=0 
		end
end




/*
   -------------------------------------------------------------------------------------------
   Enable SQL INSERTs to store values to those tags
   -------------------------------------------------------------------------------------------
*/
update SystemParameter set Value=1 where Name='AllowOriginals'
print '(Ignore any "commit" errors)'
exec aaCommitChanges
 

/*
   -------------------------------------------------------------------------------------------
   Create the SQL Agent job for updating the "Active" data
   -------------------------------------------------------------------------------------------
*/
USE [msdb]
GO
IF  EXISTS (SELECT job_id FROM msdb.dbo.sysjobs_view WHERE name = N'WWKB-Refresh Historian Client Usage Data')
EXEC msdb.dbo.sp_delete_job @job_name=N'WWKB-Refresh Historian Client Usage Data', @delete_unused_schedule=1
GO

BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'Data Collector' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'Data Collector'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
END

DECLARE @jobId BINARY(16)
select @jobId = job_id from msdb.dbo.sysjobs where (name = N'WWKB-Refresh Historian Client Usage Data')
if (@jobId is NULL)
BEGIN
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'WWKB-Refresh Historian Client Usage Data', 
		@enabled=1, 
		@notify_level_eventlog=2, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'WWKB-Refresh Historian Client Usage Data', 
		@category_name=N'Data Collector', 
		@job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
END
IF NOT EXISTS (SELECT * FROM msdb.dbo.sysjobsteps WHERE job_id = @jobId and step_id = 1)
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Refresh', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'EXEC Runtime.dbo.wwkbUsageRefreshActive', 
		@database_name=N'Runtime', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'WWKB-Every Minute', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=4, 
		@freq_subday_interval=1, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20151105, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=235959
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
GO


/*
   -------------------------------------------------------------------------------------------
   Create the SQL Agent job for updating the "Summary" data
   -------------------------------------------------------------------------------------------
*/
IF  EXISTS (SELECT job_id FROM msdb.dbo.sysjobs_view WHERE name = N'WWKB-Refresh Historian Client Usage Summaries')
EXEC msdb.dbo.sp_delete_job @job_name=N'WWKB-Refresh Historian Client Usage Summaries', @delete_unused_schedule=1
GO

BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
END

DECLARE @jobId BINARY(16)
select @jobId = job_id from msdb.dbo.sysjobs where (name = N'WWKB-Refresh Historian Client Usage Summaries')
if (@jobId is NULL)
BEGIN
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'WWKB-Refresh Historian Client Usage Summaries', 
		@enabled=1, 
		@notify_level_eventlog=2, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'WWKB-Refresh Historian Client Usage Summaries', 
		@category_name=N'[Uncategorized (Local)]', 
		@job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
END
IF NOT EXISTS (SELECT * FROM msdb.dbo.sysjobsteps WHERE job_id = @jobId and step_id = 1)
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Refresh', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'EXEC Runtime.dbo.wwkbUsageRefreshSummary', 
		@database_name=N'Runtime', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'WWKB-Every Day', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=1, 
		@freq_subday_interval=0, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20151105, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=235959
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
GO


/*
delete Runtime.dbo.Tag where TagName like 'wwkbUsage%'
*/
