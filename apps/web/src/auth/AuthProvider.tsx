import { createContext, useEffect, useRef, useState, type ReactNode } from 'react'
import type { Session } from '@supabase/supabase-js'
import { supabase } from '@/lib/supabaseClient'
import { startSync, stopSync } from '@/sync/engine'

export type AuthState = {
  session: Session | null
  loading: boolean
}

export const AuthContext = createContext<AuthState>({ session: null, loading: true })

/**
 * Resolves the initial session once, then tracks sign-in/out/refresh via
 * onAuthStateChange. Children render `loading: true` until getSession()
 * settles, so RequireAuth never briefly flashes a login screen for an
 * already-authenticated user on reload.
 *
 * Also owns the sync engine's lifecycle: start on sign-in, stop on sign-out.
 * Guarded by `syncedUserIdRef` so a TOKEN_REFRESHED event for the same user
 * doesn't tear down and rebuild the realtime channel.
 */
export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null)
  const [loading, setLoading] = useState(true)
  const syncedUserIdRef = useRef<string | null>(null)

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session)
      setLoading(false)
    })

    const { data: subscription } = supabase.auth.onAuthStateChange((_event, newSession) => {
      setSession(newSession)
    })

    return () => subscription.subscription.unsubscribe()
  }, [])

  useEffect(() => {
    const userId = session?.user.id ?? null

    if (userId && syncedUserIdRef.current !== userId) {
      syncedUserIdRef.current = userId
      void startSync(userId)
    } else if (!userId && syncedUserIdRef.current !== null) {
      syncedUserIdRef.current = null
      void stopSync()
    }
  }, [session])

  return <AuthContext.Provider value={{ session, loading }}>{children}</AuthContext.Provider>
}
