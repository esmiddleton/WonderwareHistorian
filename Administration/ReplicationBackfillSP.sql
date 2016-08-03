/*


!!! This script makes UNSUPPORTED modifications to your Runtime database !!!
!!!                       USE AT YOUR OWN RISK                           !!!

*/


-- The stored procedure below will create synch queue entries for ALL configured replication for the specified time period
-- on the indicated Replication Server. This has the effect of "back replicating" one day at a time, starting with the most
-- recent time and moving backwards. This stored procedure is a long-running one that incorporates significant wait time
-- for the Historian Replication processing to complete before adding more backfill items. It tracks/reports
-- progress using entries in the "Annotation" table for the "SysReplicationSyncQueueItemsN" tag, where "N" is the key of
-- the Replication Server.
--
-- WARNINGS
--
-- Although this leverages a supported feature (queued replication), it can apply a heavier load on the system than is
-- typical of normal queued replication and does not have any protections against overuse and repeated use for the same
-- time period.
--
/*
exec wwkbBackfillReplication '2015-12-04 00:00', '2015-12-18 00:00:00', 2
select ReplicationServerKey, ReplicationServerName, count(*) from ReplicationSyncRequestInfo group by ReplicationServerKey, ReplicationServerName
select * from ReplicationSyncRequestInfo where ReplicationServerKey=3
select * from ReplicationServer
select * from Annotation where Content like (select '%'+ReplicationServerName+'%' from ReplicationServer where ReplicationServerKey=3)
select ReplicationServerName, EarliestExecutionDateTimeUtc, ModStartDateTimeUtc, Minutes=datediff(minute,ModStartDateTimeUtc,ModEndDateTimeUtc), Tags=Count(*) from ReplicationSyncRequestInfo group by ReplicationServerName, EarliestExecutionDateTimeUtc, ModStartDateTimeUtc, Minutes=datediff(minute,ModStartDateTimeUtc,ModEndDateTimeUtc) order by EarliestExecutionDateTimeUtc desc, Minutes desc

*/
use Runtime
if not exists (select * from sys.objects where object_id = OBJECT_ID(N'[dbo].[wwkbBackfillReplication]') and type in (N'P', N'PC'))
	begin
		exec dbo.sp_executesql @statement = N'create procedure [dbo].[wwkbBackfillReplication] as' 
	end
go
alter procedure wwkbBackfillReplication (
	@OldestTimeUtc datetime, -- The oldest time for which to backfill, expressed in UTC
	@NewestTimeUtc datetime, -- The newest time for which to backfill, expressed in UTC
	@ReplicationKey int -- The key from the "ReplicationServer" table
 )
as
begin
	set nocount on
	--set @OldestTimeUtc = '2015-12-04 00:00'
	--set @NewestTimeUtc = '2016-01-11 19:15'
	--set @ReplicationKey = 3

	declare @WaitTime nvarchar(10)
	declare @MaxWaitCount int
	declare @MaxQueueReady int

	set @WaitTime='00:02:00' -- 2 minute wait between checking the queue level
	set @MaxWaitCount=500 -- Wait this many times for the queue to be cleared before timing out
	set @MaxQueueReady=30 -- Queue is ready for more when it has no more than this many entries

	-- A template to use for entries made to the "Annotation" table to track status
	declare @InvocationId nvarchar(50)
	select @InvocationId=convert(nvarchar(30),getdate(),120) + ' for ''' + ReplicationServerName + '''' from ReplicationServer where ReplicationServerKey=@ReplicationKey

	-- The start/end times for the next set of replication queue entries (normally 24-hours at a time)
	declare @CurrentStartUtc datetime
	declare @CurrentEndUtc datetime

	set @CurrentStartUtc = dateadd(d, 0, datediff(d, 0, @NewestTimeUtc)) -- Midnight (UTC) on the first day
	set @CurrentEndUtc = @NewestTimeUtc
	if @CurrentStartUtc = @CurrentEndUtc
		set @CurrentStartUtc = dateadd(d, -1, @CurrentEndUtc)

	-- The current size of the replication synch queue
	declare @QueueSize int
	set @QueueSize = (select count(*) from ReplicationSyncRequest)

	if (@QueueSize <= @MaxQueueReady)	
		begin -- Queue size okay
			-- Track how many times we've checked on the progress
			declare @WaitCount int

			-- Flag to indicate the entire backfill has completed (or timed out)
			declare @AllDone bit
			set @AllDone=0

			while (@AllDone = 0)
				begin
					-- Make sure it doesn't go too far back
					if @CurrentStartUtc < @OldestTimeUtc
						set @CurrentStartUtc = @OldestTimeUtc

					-- Add sync queue entries
					insert into ReplicationSyncRequest
						([ReplicationTagEntityKey]
						,[RequestVersion]
						,[ModStartDateTimeUtc]
						,[ModEndDateTimeUtc]
						,[EarliestExecutionDateTimeUtc]
						,[ExecuteState])
						select ReplicationTagEntityKey, 0, dateadd(millisecond,1,@CurrentStartUtc), @CurrentEndUtc,GETUTCDATE(),0 --2
						from ReplicationTagEntity where ReplicationServerKey=@ReplicationKey

					-- Report progress via the "Annotation" table
					insert Annotation (TagName, Content, UserKey, DateTime) 
						values('SysReplicationSyncQueueItems'+cast(@ReplicationKey as nvarchar(5)), 
						@InvocationId+' added entries for ''' + convert(nvarchar(30),@CurrentStartUtc,120)+'''',
						dbo.faaUser_ID(), getdate())

					-- Give Replication some time to process the items just added to the queue
					set @WaitCount = 0
					set @QueueSize = (select count(*) from ReplicationSyncRequest)
					while @WaitCount < @MaxWaitCount and @QueueSize > @MaxQueueReady
						begin
							set @WaitCount = @WaitCount + 1
							waitfor delay @WaitTime
							set @QueueSize = (select count(*) from ReplicationSyncRequest)
							print convert(nvarchar(50),getdate(),120)+ ' Waiting...' + convert(nvarchar(10),@QueueSize)
						end

					-- Move on to the previous day
					set @CurrentEndUtc = @CurrentStartUtc
					set @CurrentStartUtc = dateadd(d, -1, @CurrentEndUtc)

					if @QueueSize > @MaxQueueReady
						begin
							insert Annotation (TagName, Content, UserKey, DateTime) 
								values('SysReplicationSyncQueueItems'+cast(@ReplicationKey as nvarchar(5)), 
								@InvocationId+' backfill timed out',
								dbo.faaUser_ID(), getdate())
							print 'Timed out, exiting...'
							set @AllDone = 1
						end
					else if @CurrentEndUtc <= @OldestTimeUtc
						begin
							insert Annotation (TagName, Content, UserKey, DateTime) 
								values('SysReplicationSyncQueueItems'+cast(@ReplicationKey as nvarchar(5)), 
								@InvocationId+' completed',
								dbo.faaUser_ID(), getdate())
							print 'Completed, exiting...'
							set @AllDone = 1
						end
				end -- While not done
		end -- If queue size okay
	else
		print 'Queue size '+cast(@QueueSize as varchar(10))+' is too high to start...wait and retry later.'
	print getdate()
end
