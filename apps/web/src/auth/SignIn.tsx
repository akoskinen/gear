import { useEffect, useState } from 'react';
import { isSignInWithEmailLink } from 'firebase/auth';
import { auth } from '../lib/firebase';
import { useAuth, EMAIL_LINK_STORAGE_KEY } from './AuthProvider';

export function SignIn() {
  const { signInWithGoogle, signInWithApple, sendEmailLink, completeEmailLinkSignIn } = useAuth();
  const [email, setEmail] = useState('');
  const [sent, setSent] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!isSignInWithEmailLink(auth, window.location.href)) return;
    const stored = window.localStorage.getItem(EMAIL_LINK_STORAGE_KEY);
    if (stored) {
      setBusy(true);
      completeEmailLinkSignIn(stored).catch((e) => setError(String(e))).finally(() => setBusy(false));
    }
  }, [completeEmailLinkSignIn]);

  const run = (fn: () => Promise<void>) => async () => {
    setError(null); setBusy(true);
    try { await fn(); } catch (e) { setError(e instanceof Error ? e.message : String(e)); } finally { setBusy(false); }
  };

  return (
    <div className="flex min-h-dvh items-center justify-center bg-slate-950 px-4">
      <div className="w-full max-w-sm space-y-6 rounded-2xl bg-slate-900 p-8 shadow-xl">
        <div>
          <h1 className="text-2xl font-semibold text-white">Gear</h1>
          <p className="mt-1 text-sm text-slate-400">Sign in to manage your team's equipment.</p>
        </div>

        <div className="space-y-3">
          <button onClick={run(signInWithGoogle)} disabled={busy} className="w-full rounded-lg bg-white px-4 py-3 text-sm font-medium text-slate-900 disabled:opacity-50">
            Continue with Google
          </button>
          <button onClick={run(signInWithApple)} disabled={busy} className="w-full rounded-lg bg-slate-800 px-4 py-3 text-sm font-medium text-white disabled:opacity-50">
            Continue with Apple
          </button>
        </div>

        <div className="flex items-center gap-3 text-xs text-slate-500">
          <div className="h-px flex-1 bg-slate-800" /> or <div className="h-px flex-1 bg-slate-800" />
        </div>

        {sent ? (
          <p className="rounded-lg bg-slate-800 p-3 text-sm text-slate-300">
            Check {email} for a sign-in link.
          </p>
        ) : (
          <form
            onSubmit={(e) => {
              e.preventDefault();
              run(async () => { await sendEmailLink(email); setSent(true); })();
            }}
            className="space-y-3"
          >
            <input
              type="email" required value={email} onChange={(e) => setEmail(e.target.value)}
              placeholder="you@example.com"
              className="w-full rounded-lg border border-slate-700 bg-slate-800 px-4 py-3 text-sm text-white placeholder:text-slate-500 focus:border-slate-500 focus:outline-none"
            />
            <button type="submit" disabled={busy || !email} className="w-full rounded-lg border border-slate-700 px-4 py-3 text-sm font-medium text-white disabled:opacity-50">
              Send sign-in link
            </button>
          </form>
        )}

        {error && <p className="text-sm text-red-400">{error}</p>}
      </div>
    </div>
  );
}
