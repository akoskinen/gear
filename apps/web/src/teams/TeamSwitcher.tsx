import { useTeams } from './TeamProvider';

export function TeamSwitcher() {
  const { teams, activeTeamId, setActiveTeamId } = useTeams();
  const ids = Object.keys(teams);
  if (ids.length <= 1) return <span className="text-sm font-medium text-white">{activeTeamId ? teams[activeTeamId]?.name : ''}</span>;
  return (
    <select
      value={activeTeamId ?? ''}
      onChange={(e) => setActiveTeamId(e.target.value)}
      className="rounded-lg border border-slate-700 bg-slate-800 px-2 py-1 text-sm text-white"
    >
      {ids.map((id) => <option key={id} value={id}>{teams[id].name}</option>)}
    </select>
  );
}
