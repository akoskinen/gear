import { Link, Outlet } from 'react-router-dom';
import { useAuth } from '../auth/AuthProvider';
import { useTeams } from '../teams/TeamProvider';
import { TeamSwitcher } from '../teams/TeamSwitcher';
import { useMember, isManager } from '../teams/useMember';

export function AppShell() {
  const { signOut } = useAuth();
  const { activeTeamId } = useTeams();
  const { member } = useMember(activeTeamId);

  return (
    <div className="min-h-dvh bg-slate-950 text-white">
      <header className="flex items-center justify-between border-b border-slate-800 px-4 py-3">
        <div className="flex items-center gap-4">
          <Link to="/" className="font-semibold">Gear</Link>
          <TeamSwitcher />
        </div>
        <nav className="flex items-center gap-4 text-sm text-slate-300">
          <Link to="/inventory" className="hover:text-white">Inventory</Link>
          <Link to="/events" className="hover:text-white">Events</Link>
          {isManager(member?.role) && <Link to="/settings" className="hover:text-white">Settings</Link>}
          <button onClick={() => signOut()} className="text-slate-500 hover:text-white">Sign out</button>
        </nav>
      </header>
      <main className="mx-auto max-w-5xl px-4 py-8">
        <Outlet />
      </main>
    </div>
  );
}
