"""Create an isolated 49-completion fixture for a debug build; no real task edits."""
import datetime as dt
import json
import pathlib
import uuid
from zoneinfo import ZoneInfo

root = pathlib.Path.home() / ('Library/Application Support/com.empy.EmpyTood-celebration-' + uuid.uuid4().hex[:8])
root.mkdir(exist_ok=False)
source = pathlib.Path.home() / 'Library/Application Support/com.empy.EmpyTood'
sticky = json.loads((source / 'stickies.json').read_text())[0]
sticky.update(id=str(uuid.uuid4()).upper(), title='Celebration test', isVisible=True,
              frame=[[400, 350], [310, 320]],
              items=[dict(id=str(uuid.uuid4()).upper(), text='Complete to preview 50', isDone=False, indentLevel=0)])
now = dt.datetime.now(ZoneInfo('Australia/Sydney'))
previous = now - dt.timedelta(days=1)
while previous.weekday() >= 5:
    previous -= dt.timedelta(days=1)
stamp = previous.astimezone(dt.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
records = [dict(id=str(uuid.uuid4()).upper(), key=str(uuid.uuid4()).upper(), text='Fixture completion', color='cream', completedAt=stamp) for _ in range(49)]
(root / 'stickies.json').write_text(json.dumps([sticky]))
(root / 'completion_history.json').write_text(json.dumps(dict(records=records, highestCelebratedMilestone=0, celebratedDays=[])))
print(root)
