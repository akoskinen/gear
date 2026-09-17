import { Navigate, Route, Routes } from 'react-router-dom';
import { useAuth } from './auth/AuthProvider';
import { SignIn } from './auth/SignIn';
import { useTeams } from './teams/TeamProvider';
import { CreateTeam } from './teams/CreateTeam';
import { AppShell } from './components/AppShell';
import { Inventory } from './pages/Inventory';
import { Events } from './pages/Events';
import { Settings } from './pages/Settings';

function FullScreenLoading() {
  return <div className="flex min-h-dvh items-center justify-center bg-slate-950 text-slate-500">Loading…</div>;
}

export function App() {
  const { user, loading: authLoading } = useAuth();

  if (authLoading) return <FullScreenLoading />;
  if (!user) return <SignIn />;

  return <TeamGate />;
}

function TeamGate() {
  const { loading, teams, activeTeamId } = useTeams();
  if (loading) return <FullScreenLoading />;
  if (Object.keys(teams).length === 0) return <CreateTeam />;
  if (!activeTeamId) return <FullScreenLoading />;

  return (
    <Routes>
      <Route element={<AppShell />}>
        <Route index element={<Navigate to="/inventory" replace />} />
        <Route path="inventory" element={<Inventory />} />
        <Route path="events" element={<Events />} />
        <Route path="settings" element={<Settings />} />
        <Route path="*" element={<Navigate to="/inventory" replace />} />
      </Route>
    </Routes>
  );
}
