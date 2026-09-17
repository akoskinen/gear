import { createContext, useContext, useEffect, useState, type ReactNode } from 'react';
import { onAuthStateChanged, sendSignInLinkToEmail, signInWithEmailLink, signInWithPopup, signOut as fbSignOut, isSignInWithEmailLink, type User } from 'firebase/auth';
import { auth, googleProvider, appleProvider } from '../lib/firebase';

interface AuthState {
  user: User | null;
  loading: boolean;
  signInWithGoogle: () => Promise<void>;
  signInWithApple: () => Promise<void>;
  sendEmailLink: (email: string) => Promise<void>;
  completeEmailLinkSignIn: (email: string) => Promise<void>;
  signOut: () => Promise<void>;
}

const AuthContext = createContext<AuthState | null>(null);

const EMAIL_LINK_STORAGE_KEY = 'gear:signInEmail';

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => onAuthStateChanged(auth, (u) => { setUser(u); setLoading(false); }), []);

  const value: AuthState = {
    user,
    loading,
    signInWithGoogle: async () => { await signInWithPopup(auth, googleProvider); },
    signInWithApple: async () => { await signInWithPopup(auth, appleProvider); },
    sendEmailLink: async (email) => {
      await sendSignInLinkToEmail(auth, email, { url: window.location.href, handleCodeInApp: true });
      window.localStorage.setItem(EMAIL_LINK_STORAGE_KEY, email);
    },
    completeEmailLinkSignIn: async (email) => {
      if (!isSignInWithEmailLink(auth, window.location.href)) return;
      await signInWithEmailLink(auth, email, window.location.href);
      window.localStorage.removeItem(EMAIL_LINK_STORAGE_KEY);
      window.history.replaceState(null, '', window.location.pathname);
    },
    signOut: () => fbSignOut(auth),
  };

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthState {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used within AuthProvider');
  return ctx;
}

export { EMAIL_LINK_STORAGE_KEY };
