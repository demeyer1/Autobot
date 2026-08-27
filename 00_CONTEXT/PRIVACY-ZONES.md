# Privacy zones

AutoAssist separates context by relationship and purpose so personal life does not silently enter work and work does not flatten family or friend communication.

| Zone | Default use | Cross-zone rule |
| --- | --- | --- |
| `PRIVATE` | Sensitive personal facts, preferences, health, finances, private plans | Never shared automatically |
| `FAMILY_FRIENDS` | Personal relationships, events, logistics, and authorized communication patterns | Never used for work without an explicit current need |
| `WORK` | Organizations, projects, teammates, customers, vendors, and professional communication patterns | Never used for personal communication unless explicitly relevant |
| `SHARED` | Facts the user deliberately makes available across zones | Opt-in only, with provenance |

## Classification

1. Choose the narrowest zone that supports the task.
2. Relationship controls personal communication context. Purpose controls work context. Channel alone never decides the zone.
3. If a fact spans zones, keep separate scoped records or put only the minimum explicitly reusable fact in `SHARED`.
4. A zone label is not permission to read every file in that zone.

## Stronger isolation option

The default install uses owner-only folders inside one macOS account. Users who need stronger separation should create separate macOS user accounts or separate dedicated laptops for materially different trust domains. AutoAssist does not claim that folder permissions inside one logged-in account are equivalent to hardware or operating-system account isolation.

