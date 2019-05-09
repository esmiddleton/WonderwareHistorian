/*
Characterize Tag Version Growth
===============================
Frequent updates to tag meta data (engineering units, description, etc.) can degrade performance
due to the growth in "tag versions". These "tag versions" are captured in the "TagHistory" table.
These queries help characterize those meta data changes, which may point to some accidental changes.
Revised: 9-May-2019
By: E. Middleton
*/
use Runtime

-- This shows the tags with the most changes and calls out the most likely properties to be triggering them
select TagName, 
Versions=count(*), 
Descriptions=count(distinct [Description]), 
Units=count(distinct Unit), 
MinEUChanges=count(distinct MinEU),
MaxEUChanges=count(distinct MaxEU),
First=min(DateCreated),
Last=max(DateCreated),
AvgLifeInSecs=datediff(second,min(DateCreated),max(DateCreated))/1.0/count(*)
from TagHistory
group by TagName
having count(*)>1
order by Versions desc, Descriptions desc

-- This query helps identify the time period when the most changes occurred for each tag. 
-- Further refine this be changing all 4 of the "month" literals below to "day" or "hour"
-- May also want to narrow the period or tag list with changes to the WHERE clause
select Beginning=dateadd(month, datediff(month, 0, DateCreated), 0), TagName, Versions=Count(*)
from TagHistory
where TagName like '%'
and DateCreated between '2000-01-01' and getdate()
group by dateadd(month, datediff(month, 0, DateCreated), 0), TagName
having count(*)>5
order by Versions desc


