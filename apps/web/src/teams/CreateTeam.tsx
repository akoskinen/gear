import { useState } from 'react';
import { createTeamCall } from '../lib/callables';
import { useTeams } from './TeamProvider';

export function CreateTeam() {
  const { setActiveTeamId } = useTeams();
  const [name, setName] = useState('');
  const [shortName, setShortName] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setBusy(true); setError(null);
    try {
      const { data } = await createTeamCall({ name, shortName: shortName || name.slice(0, 12).toUpperCase() });
      setActiveTeamId(data.teamId);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="flex min-h-dvh items-center justify-center bg-slate-950 px-4">
      <form onSubmit={submit} className="w-full max-w-sm space-y-5 rounded-2xl bg-slate-900 p-8 shadow-xl">
        <div>
          <h1 className="text-xl font-semibold text-white">Create your team</h1>
          <p className="mt-1 text-sm text-slate-400">You'll get a starter inventory setup, HQ location and essentials checklist.</p>
        </div>
        <label className="block text-sm text-slate-300">
          Team name
          <input value={name} onChange={(e) => setName(e.target.value)} required placeholder="Lift Foils Racing"
            className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-white focus:border-slate-500 focus:outline-none" />
        </label>
        <label className="block text-sm text-slate-300">
          Short name
          <input value={shortName} onChange={(e) => setShortName(e.target.value.toUpperCase())} maxLength={12} placeholder="LIFT"
            className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-white focus:border-slate-500 focus:outline-none" />
        </label>
        {error && <p className="text-sm text-red-400">{error}</p>}
        <button type="submit" disabled={busy || !name} className="w-full rounded-lg bg-white px-4 py-3 text-sm font-medium text-slate-900 disabled:opacity-50">
          {busy ? 'Creating…' : 'Create team'}
        </button>
      </form>
    </div>
  );
}
