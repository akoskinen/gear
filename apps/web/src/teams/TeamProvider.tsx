import { createContext, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import { doc, onSnapshot } from 'firebase/firestore';
import type { MemberRole, RiderTier } from '@gear/shared';
import { db } from '../lib/firebase';
import { useAuth } from '../auth/AuthProvider';

export interface TeamMembership { name: string; shortName: string; role: MemberRole; tier: RiderTier }

interface TeamState {
  loading: boolean;
  /** teamId -> membership, kept current by the onMemberWritten Cloud Function. */
  teams: Record<string, TeamMembership>;
  activeTeamId: string | null;
  setActiveTeamId: (id: string) => void;
}

const TeamContext = createContext<TeamState | null>(null);
const ACTIVE_TEAM_KEY = 'gear:activeTeamId';

export function TeamProvider({ children }: { children: ReactNode }) {
  const { user } = useAuth();
  const [teams, setTeams] = useState<Record<string, TeamMembership>>({});
  const [loading, setLoading] = useState(true);
  const [activeTeamId, setActiveTeamIdState] = useState<string | null>(() => window.localStorage.getItem(ACTIVE_TEAM_KEY));

  useEffect(() => {
    if (!user) { setTeams({}); setLoading(false); return; }
    setLoading(true);
    return onSnapshot(doc(db, 'gearUsers', user.uid), (snap) => {
      setTeams((snap.data()?.teams as Record<string, TeamMembership>) ?? {});
      setLoading(false);
    });
  }, [user]);

  useEffect(() => {
    const ids = Object.keys(teams);
    if (ids.length === 0) return;
    if (!activeTeamId || !teams[activeTeamId]) setActiveTeamIdState(ids[0]);
  }, [teams, activeTeamId]);

  const setActiveTeamId = (id: string) => {
    setActiveTeamIdState(id);
    window.localStorage.setItem(ACTIVE_TEAM_KEY, id);
  };

  const value = useMemo(() => ({ loading, teams, activeTeamId, setActiveTeamId }), [loading, teams, activeTeamId]);
  return <TeamContext.Provider value={value}>{children}</TeamContext.Provider>;
}

export function useTeams(): TeamState {
  const ctx = useContext(TeamContext);
  if (!ctx) throw new Error('useTeams must be used within TeamProvider');
  return ctx;
}
