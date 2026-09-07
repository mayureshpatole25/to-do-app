"""One-time, backup-first consolidation. Run only with Empy Tood quit.

The direct store is authoritative. Missing legacy items go into recovered
archives; conflicting versions never overwrite the current task state.
"""
import copy
import datetime as dt
import json
import pathlib
import shutil
import uuid

home = pathlib.Path.home()
direct = home / 'Library/Application Support/com.empy.EmpyTood'
legacy = home / 'Library/Containers/com.empy.EmpyTood/Data/Library/Application Support/com.empy.EmpyTood'


def read(root, name, default):
    path = root / name
    return json.loads(path.read_text()) if path.exists() else default


def write(root, name, value):
    temporary = root / (name + '.consolidating')
    temporary.write_text(json.dumps(value, indent=2, ensure_ascii=False))
    temporary.replace(root / name)


def main():
    if legacy.is_symlink():
        assert legacy.resolve() == direct.resolve()
        print('Already consolidated; both paths resolve to the canonical store.')
        return
    assert direct.is_dir() and legacy.is_dir()
    timestamp = dt.datetime.now().strftime('%Y%m%d-%H%M%S')
    backup = direct.parent / ('EmpyTood-consolidation-backup-' + timestamp)
    backup.mkdir()
    shutil.copytree(direct, backup / 'authoritative')
    shutil.copytree(legacy, backup / 'legacy')

    live = read(direct, 'stickies.json', [])
    archives = read(direct, 'archived_stickies.json', [])
    all_current = live + [entry['data'] for entry in archives]
    known = {item['id'] for sticky in all_current for item in sticky['items']}
    original_live = copy.deepcopy(live)
    now = dt.datetime.now(dt.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    recovered = 0
    for sticky in read(legacy, 'stickies.json', []) + [e['data'] for e in read(legacy, 'archived_stickies.json', [])]:
        missing = [i for i in sticky['items'] if i['id'] not in known and i['text'].strip()]
        if not missing:
            continue
        data = copy.deepcopy(sticky)
        data.update(id=str(uuid.uuid4()).upper(), title='Recovered · ' + sticky['title'], items=missing, isVisible=False)
        archives.append(dict(id=data['id'], data=data, archivedAt=now))
        recovered += len(missing)
        known.update(i['id'] for i in missing)

    # Preserve early retired completion archives in the new durable history.
    history = read(direct, 'completion_history.json', dict(records=[], highestCelebratedMilestone=0, celebratedDays=[]))
    keys = {entry['key'] for entry in history['records']}

    def add(item_id, text, color, date, scheduled=None):
        if not date or not text.strip():
            return
        key = item_id + (':' + scheduled if scheduled else '')
        if key not in keys:
            keys.add(key)
            history['records'].append(dict(id=str(uuid.uuid4()).upper(), key=key, text=text, color=color, completedAt=date))

    for sticky in live + [entry['data'] for entry in archives]:
        for item in sticky['items']:
            if item.get('isDone'):
                add(item['id'], item['text'], sticky['colorID'], item.get('completedAt'), item.get('dueDate') if item.get('recurrence') else None)
            for occurrence in item.get('occurrenceHistory', []):
                if occurrence.get('wasCompleted'):
                    add(item['id'], item['text'], sticky['colorID'], occurrence.get('completedAt'), occurrence['scheduledAt'])
    historical = 0
    for root in (direct, legacy):
        for path in sorted(root.rglob('archive*.json')):
            if path.name == 'archived_stickies.json':
                continue
            for item in json.loads(path.read_text()):
                if 'completedAt' in item and item['id'] not in known:
                    before = len(keys)
                    add(item['id'], item['text'], 'cream', item['completedAt'])
                    historical += len(keys) - before

    journals = read(direct, 'journal.json', [])
    days = {e['day'] for e in journals}
    for entry in read(legacy, 'journal.json', []):
        if entry['day'] not in days:
            journals.append(entry)
            days.add(entry['day'])
    history['highestCelebratedMilestone'] = max(history['highestCelebratedMilestone'], len(history['records']) // 50 * 50)
    write(direct, 'archived_stickies.json', archives)
    write(direct, 'journal.json', journals)
    write(direct, 'completion_history.json', history)
    assert read(direct, 'stickies.json', []) == original_live, 'Live task state changed unexpectedly'
    assert len(keys) == len(history['records'])
    # Retire the second writable store; old paths now reach the same files.
    legacy.rename(backup / 'legacy-retired-original')
    legacy.symlink_to(direct, target_is_directory=True)
    assert (legacy / 'stickies.json').samefile(direct / 'stickies.json')
    print(json.dumps(dict(backup=str(backup), canonical=str(direct), recovered_items=recovered,
                         historical_completions=historical, total_completions=len(history['records']),
                         live_stickies=len(live)), indent=2))


if __name__ == '__main__':
    main()
