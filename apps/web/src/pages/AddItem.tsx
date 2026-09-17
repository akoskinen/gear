import { useEffect, useState } from 'react';
import { collection, doc, getDoc, getDocs, query, setDoc, where } from 'firebase/firestore';
import type { GearCategory, Item, Team } from '@gear/shared';
import { db } from '../lib/firebase';

const CATEGORIES: { value: GearCategory; label: string }[] = [
  { value: 'board', label: 'Board' }, { value: 'mast', label: 'Mast' }, { value: 'front_wing', label: 'Front wing' },
  { value: 'stabilizer', label: 'Stabilizer' }, { value: 'fuselage', label: 'Fuselage' }, { value: 'propulsion', label: 'Propulsion' },
  { value: 'battery', label: 'Battery' }, { value: 'controller', label: 'Controller' }, { value: 'charger', label: 'Charger' }, { value: 'spare', label: 'Spare' },
];

interface LocationOption { id: string; name: string }

export function AddItemDialog({ teamId, onClose }: { teamId: string; onClose: () => void }) {
  const [category, setCategory] = useState<GearCategory>('board');
  const [model, setModel] = useState('');
  const [labelCode, setLabelCode] = useState('');
  const [labelTouched, setLabelTouched] = useState(false);
  const [locations, setLocations] = useState<LocationOption[]>([]);
  const [locationId, setLocationId] = useState('');
  const [addAnother, setAddAnother] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    getDocs(query(collection(db, 'gearTeams', teamId, 'locations'), where('archivedAt', '==', null))).then((snap) => {
      const opts = snap.docs.map((d) => ({ id: d.id, name: d.data().name as string }));
      setLocations(opts);
      if (opts[0]) setLocationId(opts[0].id);
    });
  }, [teamId]);

  // Suggest the next label code from the team's prefix scheme, e.g. BAT-08, once existing codes for
  // this category are known. Kept simple: count existing + 1. Axel can override before saving.
  useEffect(() => {
    if (labelTouched) return;
    (async () => {
      const teamSnap = await getDoc(doc(db, 'gearTeams', teamId));
      const prefixes = (teamSnap.data() as Team | undefined)?.labelPrefixes;
      const p = prefixes?.[category];
      if (!p) return;
      const existing = await getDocs(query(collection(db, 'gearTeams', teamId, 'items'), where('category', '==', category)));
      const next = existing.size + 1;
      setLabelCode(`${p.prefix}-${String(next).padStart(p.seqWidth, '0')}`);
    })();
  }, [teamId, category, labelTouched]);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setBusy(true); setError(null);
    try {
      const itemsRef = collection(db, 'gearTeams', teamId, 'items');
      const item: Item = {
        category, labelCode, model, spec: {}, serial: null, ownerMemberId: null,
        homeLocationId: locationId || null, locationId: locationId || null, holderMemberId: null,
        status: 'ready', statusReason: null, expectedBackOn: null, batteryTypeId: null, firmwareVersion: null,
        cycleCount: 0, chargerSpeedFactor: null, battery: category === 'battery' ? { lastReading: null, charging: null } : null,
        photos: [], createdAt: Date.now(), retiredAt: null, lastMovementAt: null,
      };
      await setDoc(doc(itemsRef, crypto.randomUUID()), item);
      if (addAnother) { setLabelCode(''); setLabelTouched(false); setModel(''); }
      else onClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="fixed inset-0 z-10 flex items-center justify-center bg-black/60 px-4">
      <form onSubmit={submit} className="w-full max-w-md space-y-4 rounded-2xl bg-slate-900 p-6 shadow-xl">
        <div className="flex items-center justify-between">
          <h2 className="text-lg font-semibold text-white">Add item</h2>
          <button type="button" onClick={onClose} className="text-slate-500 hover:text-white">✕</button>
        </div>

        <label className="block text-sm text-slate-300">
          Category
          <select value={category} onChange={(e) => setCategory(e.target.value as GearCategory)}
            className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-white">
            {CATEGORIES.map((c) => <option key={c.value} value={c.value}>{c.label}</option>)}
          </select>
        </label>

        <label className="block text-sm text-slate-300">
          Model
          <input value={model} onChange={(e) => setModel(e.target.value)} required placeholder="Lift 4'2 Race"
            className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-white" />
        </label>

        <label className="block text-sm text-slate-300">
          Label code
          <input value={labelCode} onChange={(e) => { setLabelCode(e.target.value.toUpperCase()); setLabelTouched(true); }} required
            className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 font-mono text-white" />
        </label>

        <label className="block text-sm text-slate-300">
          Location
          <select value={locationId} onChange={(e) => setLocationId(e.target.value)}
            className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-white">
            {locations.map((l) => <option key={l.id} value={l.id}>{l.name}</option>)}
          </select>
        </label>

        <label className="flex items-center gap-2 text-sm text-slate-300">
          <input type="checkbox" checked={addAnother} onChange={(e) => setAddAnother(e.target.checked)} />
          Add another like this after saving
        </label>

        {error && <p className="text-sm text-red-400">{error}</p>}

        <button type="submit" disabled={busy || !model || !labelCode} className="w-full rounded-lg bg-white px-4 py-2 text-sm font-medium text-slate-900 disabled:opacity-50">
          {busy ? 'Saving…' : 'Save item'}
        </button>
      </form>
    </div>
  );
}
