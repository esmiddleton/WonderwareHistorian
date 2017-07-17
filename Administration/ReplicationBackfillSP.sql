/*


!!! This script makes UNSUPPORTED modifications to your Runtime database !!!
!!!                       USE AT YOUR OWN RISK                           !!!

Description
-----------
The stored procedure below will create synch queue entries for configured replication tags for the specified time period
on the indicated Replication Server. It can optionally include a tagname filter. Adding these queue entries has the 
effect of "back replicating" one day at a time, starting with the most recent time and moving backwards. 

This stored procedure is a long-running one that incorporates significant wait time
for the Historian Replication processing to complete before adding more backfill items. It tracks/reports
progress using entries in the "Annotation" table for the "SysReplicationSyncQueueItemsN" tag, where "N" is the key of
the Replication Server. 

To prepare your Historian for back-replication, copy this entire script into a "New Query" window in SQL Server Management Studio
and press "Execute". That will create the stored procedure and all its dependencies. You can then execute the stored procedure as 
described below under "Usage".


Usage
-----

	exec wwkbBackfillReplication <Oldest Time>, <Newest Time>, <Replication Server Key>, <Minimum Period>, <Tag Filter>

Where:

	Oldest Time / Newest Time 
		Time period expressed in local server time

	Replication Server Key
		The key of the target "tier 2". You can find the key for a replication server by querying the "tier 1" using:
			select * from ReplicationServer

	Minimum Period (in minutes--optional)
		Will only queue entries for summary replication periods longer then the specified number of minutes. If omitted,
		the period will depend upon the overall replication duration specified above. Use "0" to queue items for "simple"
		replication (all raw values)

	Tag Filter (optional--defaults to ALL tags)
		A tag name filter for the source tag. Uses the same syntax as a SQL "LIKE" clause

Examples

	exec wwkbBackfillReplication '2016-04-01 00:00', '2016-04-10 0:00:00', 1
	exec wwkbBackfillReplication '2016-04-01 00:00', '2016-04-10 0:00:00', 1, 0, '%.PV'


Limitations
-----------
The design of the "queued replication" leveraged by this stored procedure addresses recovering from occassional communications 
outages between the "tier 1" source Historian and the "tier 2". Used incorrectly, this stored procedure can overload the 
queued replication system, either by adding excessive query load on the "tier 1" or by distributing the data sent to "tier 2" 
across too broad of time period all at once. There are safeguards included in the stored procedure to protect against those
cases, but do not attempt to circumvent them.


License
-------
This script can be used without additional charge with any licensed Wonderware Historian server. 
The terms of use are defined in your existing End User License Agreement for the 
Wonderware Historian software.

Update Info
-----------
The latest version of this script is available at:
	https://github.com/esmiddleton/WonderwareHistorian/tree/master/Administration


Modified: 17-Jul-2017
By:		  E. Middleton

*/

/*
-- The following queries are useful for checking & monitoring the Replication Queue

select * from ReplicationSyncRequestInfo where ReplicationServerKey=2   order by earliestexecutiondatetimeUtc desc
update ReplicationSyncRequestInfo set earliestexecutiondatetimeUtc=getutcdate() where ModEndDateTimeUtc < dateadd(minute,-5,getutcdate())
update ReplicationSyncRequestInfo set earliestexecutiondatetimeUtc=getutcdate(), RequestVersion=0 where ReplicationServerKey=2
delete ReplicationSyncRequest where ModEndDateTimeUtc<'2016-01-01'
select * from ReplicationServer
select top 100 * from Annotation where Content like (select '%'+ReplicationServerName+'%' from ReplicationServer where ReplicationServerKey=1) order by DateCreated desc

*/
use Runtime
exec aaUserDetailUpdate
go

if not exists (select * from sys.objects where object_id = OBJECT_ID(N'[dbo].[wwkbBackfillReplication]') and type in (N'P', N'PC'))
	begin
		exec dbo.sp_executesql @statement = N'create procedure [dbo].[wwkbBackfillReplication] as' 
	end
go
alter procedure wwkbBackfillReplication (
	@OldestTimeLocal datetime, -- The oldest time for which to backfill, expressed in server local time
	@NewestTimeLocal datetime, -- The newest time for which to backfill, expressed in server local time
	@ReplicationKey int, -- The key from the "ReplicationServer" table
	@LeastMinuteLimit int=null, -- Only backfill for summary tags that have a period longer than this. Use "0" to include "simple" replicationed tags
	@TagNameFilter nvarchar(50)='%' -- Only backfill source tags which match this filter
 )
as
begin
	set nocount on
	if @NewestTimeLocal > getdate()
		set @NewestTimeLocal = getdate()

	declare @WaitTime nvarchar(10)
	declare @MaxWaitCount int
	declare @MaxQueueReady int

	set @WaitTime='00:01:00' -- 1-minute wait between checking the queue level
	set @MaxWaitCount=240 -- Wait this many times for the queue to be cleared before timing out

	-- Prepare for reporting progress through an annotation on a system tag
	declare @RepTag nvarchar(50)
	declare @RepComment nvarchar(1000)
	declare @TimeStampedComment nvarchar(1000)
	set @RepTag = 'SysReplicationSyncQueueItems'+cast(@ReplicationKey as nvarchar(5))

	-- The current size of the replication synch queue
	declare @QueueSize int
	set @QueueSize = (select count(*) from ReplicationSyncRequestInfo where ReplicationServerKey=@ReplicationKey)
	set @MaxQueueReady= @QueueSize + 250 -- Queue is ready for more when it has no more than this many entries

	-- Add some protections against running the backfill after there are already older entries in the queue
	declare @OldEntries int;
	declare @QueueDays int
	select @OldEntries=count(*), @QueueDays=datediff(day,min(ModStartDateTimeUtc), max(ModEndDateTimeUtc)) 
		 from ReplicationSyncRequestInfo 
		 where ReplicationServerKey=@ReplicationKey 
		 and datediff(day,ModEndDateTimeUtc,getutcdate()) > 3

	if (@OldEntries > 0)
		begin
			print 'There are already '+convert(nvarchar(10),@OldEntries)+' entries for the period before '+convert(nvarchar(30),dateadd(day,-7,getdate()),120)+' in the queue.'
			print 'Do NOT re-run this procedure for the same tags and time period.'
			print 'If you really understand the ramifications and intend to re-run it for the same period,'
			print 'wait for these older queue entries to be processed and re-run the procedure.'
			print 'Exiting without adding any backfill requests.'
			set @RepComment = '*** Too many old entries already in the queue: '+convert(nvarchar(10),@OldEntries)
			exec aaAnnotationInsert @RepTag, null, null, null, @RepComment
			return
		end



	-- Add some protections against overloading the queue from the start
	if (@QueueSize > 500) 
		begin
			print 'There are already too many entries ('+convert(nvarchar(10),@QueueSize)+') in the replication queue for this server.'
			print 'Wait for this to fall below 500 and re-run the procedure.'
			print 'Exiting without adding any backfill requests.'
			set @RepComment = '*** Too many overall entries already in the queue: '+convert(nvarchar(10),@QueueSize)
			exec aaAnnotationInsert @RepTag, null, null, null, @RepComment
			return
		end

	-- Add some protections against a queue distributed across too much time (can be a problem for the "tier 2")
	if (@QueueDays > 5) 
		begin
			print 'There are entries spanning too many days ('+convert(nvarchar(10),@QueueDays)+' days) already in the replication queue for this server.'
			print 'Wait for this to fall below 15 days and re-run the procedure to avoid overloading the "tier 2" server.'
			print 'Exiting without adding any backfill requests.'
			set @RepComment = '*** Existing entries spanning too many days already in the queue: '+convert(nvarchar(10),@QueueDays)
			exec aaAnnotationInsert @RepTag, null, null, null, @RepComment
			return
		end

	-- A template to use for entries made to the "Annotation" table to track status
	declare @InvocationId nvarchar(100)
	select @InvocationId=convert(nvarchar(30),getdate(),120) + ' for ''' + ReplicationServerName + '''' from ReplicationServer where ReplicationServerKey=@ReplicationKey

	-- Keep track of when we started executing, so we an estimate when we'll finish
	declare @ExecutionStartUtc datetime
	set @ExecutionStartUtc = GETUTCDATE() 

	-- The start/end times for the next set of replication queue entries (normally 24-hours at a time)
	declare @CurrentStartLocal datetime
	declare @CurrentEndLocal datetime
	declare @NextEndLocal datetime
	declare @CurrentStartUtc datetime
	declare @CurrentEndUtc datetime

	set @NextEndLocal=@NewestTimeLocal

	select top 1 @CurrentStartUtc=dateadd(minute,-TimeZoneOffset,FromDate), 
	@CurrentEndUtc=case when ToDate > getdate() then getdate() else dateadd(minute,-TimeZoneOffset,ToDate) end, 
	@NextEndLocal=FromDate, --dateadd(millisecond,-1,FromDate),
	@CurrentStartLocal=FromDate,
	@CurrentEndLocal=ToDate
	from HistoryBlock
	where datediff(minute,FromDate,@NextEndLocal) >= 0
	order by datediff(minute,FromDate,@NextEndLocal) asc, datediff(hour, FromDate, ToDate) desc

	-- Add some protections against re-running the backfill for the same period
	select @OldEntries=count(*)
		 from ReplicationSyncRequestInfo 
		 where ReplicationServerKey=@ReplicationKey 
		 and ModEndDateTimeUtc between @CurrentStartUtc and @CurrentEndUtc
		 and SourceTagName like @TagNameFilter

	if (@OldEntries > 0)
		begin
			print 'There are already '+convert(nvarchar(10),@OldEntries)+' entries for the period between '+convert(nvarchar(30),@CurrentStartLocal,120)+' and '+convert(nvarchar(30),@CurrentEndLocal,120)+'.'
			print 'Do NOT re-run this procedure for the same tags and time period.'
			print 'If you really understand the ramifications and intend to re-run it for the same period,'
			print 'wait for these older queue entries to be processed and re-run the procedure.'
			print 'Exiting without adding any backfill requests.'
			set @RepComment = '*** Too many old entries already in the queue: '+convert(nvarchar(10),@OldEntries)
			exec aaAnnotationInsert @RepTag, null, null, null, @RepComment
			return
		end
		
		-- Variables for calculating progress & estimating completion time
	declare @AverageRate float
	declare @MinutesRemaining float
	declare @MinutesElapsed float
	declare @MinutesBackfilled float
	declare @MinutesTotal float
	set @MinutesTotal = datediff(minute,@OldestTimeLocal,@NewestTimeLocal)

	-- When not specified, set a default summary limit based on the extent of the backfill
	if @LeastMinuteLimit is null
		set @LeastMinuteLimit = case
			when @MinutesTotal > 1440*90 then 60 -- More than 3 months
			when @MinutesTotal > 1440*31 then 5 -- More than one month
			when @MinutesTotal > 1440*7 then 1 -- More than one week
			else 0 end

	if (@LeastMinuteLimit>0)
		begin
			set @InvocationId = @InvocationId + ' (' + cast(@LeastMinuteLimit as nvarchar(15))+ '+ min)'
			print convert(nvarchar(50),getdate(),120)+' Only backfilling summaries of '+cast(@LeastMinuteLimit as nvarchar(15))+ ' minutes and longer.'
		end
	else
		begin
			set @InvocationId = @InvocationId + ' (all)'
			print convert(nvarchar(50),getdate(),120)+' Backfilling raw values and summaries.'
		end

	-- Track how many times we've checked on the progress
	declare @WaitCount int
	declare @LogRate int
	set @LogRate = 2

	-- Flag to indicate the entire backfill has completed (or timed out)
	declare @AllDone bit
	set @AllDone=0

	-- Find how many tags are configured to replicate
	declare @EntityCount int
	set @EntityCount = (select count(*) from ReplicationTagEntity where ReplicationServerKey=@ReplicationKey)

	-- Record start of execution in the "Annotation" table
	set @RepComment = ' Beginning backfill for ' + convert(nvarchar(10),@EntityCount) + ' tags from ''' + convert(nvarchar(30),@OldestTimeLocal,120)+''' to '''+ convert(nvarchar(30),@NewestTimeLocal,120)+''''
	print convert(nvarchar(50),getdate(),120)+@RepComment
	set @RepComment = @InvocationId + @RepComment
	exec aaAnnotationInsert @RepTag, null, null, null, @RepComment

	while (@AllDone = 0)
		begin
			-- Make sure it doesn't go too far back
			if @CurrentStartLocal < @OldestTimeLocal
				set @CurrentStartLocal = @OldestTimeLocal

			-- Add sync queue entries
			insert into ReplicationSyncRequest ([ReplicationTagEntityKey] ,[RequestVersion] ,[ModStartDateTimeUtc] ,[ModEndDateTimeUtc] ,[EarliestExecutionDateTimeUtc], [ExecuteState])
				select distinct e.ReplicationTagEntityKey, 0, dateadd(millisecond,1,@CurrentStartUtc), @CurrentEndUtc,GETUTCDATE(),0 --2
				from ReplicationTagEntity e
				join ReplicationGroup g on e.ReplicationGroupKey=g.ReplicationGroupKey
				left outer join ReplicationSyncRequest q  -- Protects against duplicating existing queue records
					on q.ReplicationTagEntityKey = e.ReplicationTagEntityKey
					and q.ModStartDateTimeUtc = @CurrentStartUtc
					and q.ModEndDateTimeUtc = @CurrentEndUtc
				left outer join IntervalReplicationSchedule i on i.ReplicationScheduleKey=g.ReplicationScheduleKey
				where e.ReplicationServerKey=@ReplicationKey
					and e.SourceTagName like @TagNameFilter
					and q.ReplicationTagEntityKey is null
					and isnull(i.Period * case i.Unit when 'Day' then 1440 when 'Hour' then 60 when 'Minute' then 1 else 0 end,0) >= @LeastMinuteLimit

			-- Report progress to console
			set @RepComment = ' Added ' + convert(nvarchar(10),@EntityCount) + ' items from ' + convert(nvarchar(50),@CurrentStartLocal,120) + ' to ' + convert(nvarchar(50),@CurrentEndLocal,120)
			set @TimeStampedComment = convert(nvarchar(50),getdate(),120)+' '+@RepComment
			raiserror (@TimeStampedComment, 0, 1) with nowait -- Used to force update in Management Studio so messages are visible

			-- Estimate time remaining
			set @MinutesBackfilled = datediff(minute,@CurrentEndLocal,@NewestTimeLocal)
			set @MinutesElapsed = datediff(minute,@ExecutionStartUtc,getutcdate())
			if (@MinutesBackfilled > 0) and (@MinutesTotal>0) and (@MinutesElapsed > 0)
				begin
					set @AverageRate = @MinutesElapsed / @MinutesBackfilled 
					set @MinutesRemaining = (@MinutesTotal - @MinutesBackfilled) * @AverageRate
					print '           Estimated overall completion time: '+convert(nvarchar(50),dateadd(minute,@MinutesRemaining,getdate()),120)
				end

			-- Record progress in the "Annotation" table
			set @RepComment = @InvocationId + @RepComment
			exec aaAnnotationInsert @RepTag, null, null, null, @RepComment

			-- Give Replication some time to process the items just added to the queue
			set @WaitCount = 0
			set @QueueSize = (select count(*) from ReplicationSyncRequestInfo where ReplicationServerKey=@ReplicationKey)
			while (@WaitCount < @MaxWaitCount and @QueueSize > @MaxQueueReady) or (@WaitCount=0)
				begin
					set @WaitCount = @WaitCount + 1
					waitfor delay @WaitTime
					if (@WaitCount % @LogRate = 0)
						begin
							set @QueueSize = (select count(*) from ReplicationSyncRequestInfo where ReplicationServerKey=@ReplicationKey)
							set @RepComment = 'Backfilling remaining ' + convert(nvarchar(10),@QueueSize) + ' items starting at ' + convert(nvarchar(50),@CurrentStartLocal,120)
							set @TimeStampedComment = convert(nvarchar(50),getdate(),120)+' '+@RepComment
							raiserror (@TimeStampedComment, 0, 1) with nowait -- Used to force update in Management Studio so messages are visible
						end
				end

			-- Move on to the previous block
			set @AllDone=1

			-- Base the time period to replicate on existing history blocks boundaries
			select top 1 @CurrentStartUtc=dateadd(minute,-TimeZoneOffset,FromDate), 
			@CurrentEndUtc=dateadd(minute,-TimeZoneOffset,ToDate), 
			@NextEndLocal=FromDate, --dateadd(minute,-1,FromDate),
			@CurrentStartLocal=FromDate,
			@CurrentEndLocal=ToDate,
			@AllDone=0
			from HistoryBlock
			where datediff(minute,FromDate,@NextEndLocal) > 0 --and datediff(minute,FromDate,@NextEndLocal) < 1441
			order by datediff(minute,FromDate,@NextEndLocal) asc, datediff(hour, FromDate, ToDate) desc

			-- Management Studio starts queuing messages above 500, so slow the logging rate after we first get started
			if (@LogRate < 10) 
				set @LogRate = case @LogRate when 2 then 5 when 5 then 10 else @LogRate end

			if @QueueSize > @MaxQueueReady
				begin -- Queue processing is taking longer than  expected--something may be wrong, so bail out
					insert Annotation (TagName, Content, UserKey, DateTime) 
						values('SysReplicationSyncQueueItems'+cast(@ReplicationKey as nvarchar(5)), 
						@InvocationId+' backfill timed out',
						dbo.faaUser_ID(), getdate())
					print convert(nvarchar(50),getdate(),120)+' Timed out after running '+convert(nvarchar(10),datediff(minute,@ExecutionStartUtc,getutcdate()))+' minutes.'
					print ' '
					print 'After the queue is cleared, you can resume with:'
					print '   wwkbBackfillReplication '''+convert(nvarchar(50),@OldestTimeLocal,120)+''', '''+convert(nvarchar(50),@NextEndLocal,120)+''''
					print 'Exiting...'
					set @AllDone = 1
				end
			else if @CurrentStartLocal < @OldestTimeLocal
				begin -- Finished the requested backfill
					insert Annotation (TagName, Content, UserKey, DateTime) 
						values('SysReplicationSyncQueueItems'+cast(@ReplicationKey as nvarchar(5)), 
						@InvocationId+' completed',
						dbo.faaUser_ID(), getdate())
					print convert(nvarchar(50),getdate(),120)+' Completed after '+convert(nvarchar(10),datediff(minute,@ExecutionStartUtc,getutcdate()))+' minutes.'
					print 'Processed '''+convert(nvarchar(50),@OldestTimeLocal,120)+''' to '''+convert(nvarchar(50),@NewestTimeLocal,120)+''''
					if (datediff(day,@OldestTimeLocal,@NewestTimeLocal)>0)
						print 'Average '+ltrim(str((datediff(second,@ExecutionStartUtc,getutcdate())/60.0)/datediff(day,@OldestTimeLocal,@NewestTimeLocal),6,1))+' minutes processing per day of historical data'
					set @AllDone = 1
				end

		end

		if (@InvocationId is NULL)
			print '**** The ID you provided for the replication server does not exist'
end
