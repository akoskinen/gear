import { useEffect, useState } from 'react';
import { doc, onSnapshot } from 'firebase/firestore';
import type { Member } from '@gear/shared';
import { db } from '../lib/firebase';
import { useAuth } from '../auth/AuthProvider';

/** The signed-in user's own member document for the active team, used to gate manager-only UI. */
export function useMember(teamId: string | null): { member: (Member & { id: string }) | null; loading: boolean } {
  const { user } = useAuth();
  const [member, setMember] = useState<(Member & { id: string }) | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!teamId || !user) { setMember(null); setLoading(false); return; }
    setLoading(true);
    return onSnapshot(doc(db, 'gearTeams', teamId, 'members', user.uid), (snap) => {
      setMember(snap.exists() ? ({ ...(snap.data() as Member), id: snap.id }) : null);
      setLoading(false);
    });
  }, [teamId, user]);

  return { member, loading };
}

export function isManager(role: Member['role'] | undefined): boolean {
  return role === 'owner' || role === 'manager';
}
