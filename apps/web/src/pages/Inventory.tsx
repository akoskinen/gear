import { useEffect, useMemo, useState } from 'react';
import { collection, onSnapshot, orderBy, query } from 'firebase/firestore';
import type { GearCategory, Item, ItemStatus } from '@gear/shared';
import { db } from '../lib/firebase';
import { useTeams } from '../teams/TeamProvider';
import { useMember, isManager } from '../teams/useMember';
import { AddItemDialog } from './AddItem';

const CATEGORY_LABEL: Record<GearCategory, string> = {
  board: 'Boards', mast: 'Masts', front_wing: 'Front wings', stabilizer: 'Stabilizers', fuselage: 'Fuselages',
  propulsion: 'Propulsion', battery: 'Batteries', controller: 'Controllers', charger: 'Chargers', spare: 'Spares',
};

const STATUS_STYLE: Record<ItemStatus, string> = {
  ready: 'bg-emerald-900 text-emerald-300',
  needs_check: 'bg-amber-900 text-amber-300',
  in_repair: 'bg-orange-900 text-orange-300',
  retired: 'bg-slate-800 text-slate-400',
};

export function Inventory() {
  const { activeTeamId } = useTeams();
  const { member } = useMember(activeTeamId);
  const [items, setItems] = useState<(Item & { id: string })[]>([]);
  const [loading, setLoading] = useState(true);
  const [showAdd, setShowAdd] = useState(false);
  const [categoryFilter, setCategoryFilter] = useState<GearCategory | 'all'>('all');

  useEffect(() => {
    if (!activeTeamId) return;
    setLoading(true);
    const q = query(collection(db, 'gearTeams', activeTeamId, 'items'), orderBy('labelCode'));
    return onSnapshot(q, (snap) => {
      setItems(snap.docs.map((d) => ({ ...(d.data() as Item), id: d.id })));
      setLoading(false);
    });
  }, [activeTeamId]);

  const visible = useMemo(() => {
    const owned = items.filter((i) => !i.ownerMemberId && !i.retiredAt);
    return categoryFilter === 'all' ? owned : owned.filter((i) => i.category === categoryFilter);
  }, [items, categoryFilter]);

  const grouped = useMemo(() => {
    const byCat = new Map<GearCategory, (Item & { id: string })[]>();
    for (const item of visible) byCat.set(item.category, [...(byCat.get(item.category) ?? []), item]);
    return byCat;
  }, [visible]);

  if (!activeTeamId) return null;

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-semibold">Inventory</h1>
        {isManager(member?.role) && (
          <button onClick={() => setShowAdd(true)} className="rounded-lg bg-white px-4 py-2 text-sm font-medium text-slate-900">
            Add item
          </button>
        )}
      </div>

      <div className="flex flex-wrap gap-2">
        <FilterChip active={categoryFilter === 'all'} onClick={() => setCategoryFilter('all')} label={`All (${items.filter((i) => !i.ownerMemberId && !i.retiredAt).length})`} />
        {(Object.keys(CATEGORY_LABEL) as GearCategory[]).map((cat) => {
          const count = items.filter((i) => i.category === cat && !i.ownerMemberId && !i.retiredAt).length;
          if (count === 0) return null;
          return <FilterChip key={cat} active={categoryFilter === cat} onClick={() => setCategoryFilter(cat)} label={`${CATEGORY_LABEL[cat]} (${count})`} />;
        })}
      </div>

      {loading ? (
        <p className="text-slate-400">Loading…</p>
      ) : visible.length === 0 ? (
        <p className="text-slate-400">No gear yet. {isManager(member?.role) ? 'Add your first item to get started.' : ''}</p>
      ) : (
        <div className="space-y-8">
          {[...grouped.entries()].map(([cat, catItems]) => (
            <section key={cat}>
              <h2 className="mb-2 text-sm font-medium uppercase tracking-wide text-slate-500">{CATEGORY_LABEL[cat]}</h2>
              <div className="overflow-hidden rounded-xl border border-slate-800">
                <table className="w-full text-sm">
                  <tbody className="divide-y divide-slate-800">
                    {catItems.map((item) => (
                      <tr key={item.id}>
                        <td className="px-4 py-3 font-mono text-slate-300">{item.labelCode}</td>
                        <td className="px-4 py-3 text-slate-200">{item.model}</td>
                        <td className="px-4 py-3 text-slate-400">
                          {item.holderMemberId ? 'with rider' : item.locationId ? 'at location' : '—'}
                        </td>
                        <td className="px-4 py-3">
                          <span className={`rounded-full px-2 py-0.5 text-xs ${STATUS_STYLE[item.status]}`}>{item.status.replace('_', ' ')}</span>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </section>
          ))}
        </div>
      )}

      {showAdd && activeTeamId && <AddItemDialog teamId={activeTeamId} onClose={() => setShowAdd(false)} />}
    </div>
  );
}

function FilterChip({ active, onClick, label }: { active: boolean; onClick: () => void; label: string }) {
  return (
    <button onClick={onClick} className={`rounded-full px-3 py-1 text-xs ${active ? 'bg-white text-slate-900' : 'bg-slate-800 text-slate-300 hover:bg-slate-700'}`}>
      {label}
    </button>
  );
}
