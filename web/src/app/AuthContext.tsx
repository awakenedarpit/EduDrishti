import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from "react";
import type { Session } from "@supabase/supabase-js";
import type { ProfileRow } from "../lib/database.types";
import { friendlyBackendError } from "../lib/backend-errors";
import { supabase } from "../lib/supabase";

type AuthContextValue = {
  session: Session | null;
  profile: ProfileRow | null;
  loading: boolean;
  profileError: string | null;
  refreshProfile: () => Promise<void>;
};

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null);
  const [profile, setProfile] = useState<ProfileRow | null>(null);
  const [loading, setLoading] = useState(true);
  const [profileError, setProfileError] = useState<string | null>(null);

  const readProfile = useCallback(async (userId: string) => {
    if (!supabase) return;
    const { data, error } = await supabase
      .from("profiles")
      .select("user_id, app_role, display_name, created_at, updated_at")
      .eq("user_id", userId)
      .maybeSingle();
    if (error) throw friendlyBackendError(error);
    setProfile(data);
    if (!data) setProfileError("Your profile is still being provisioned. Try refreshing in a moment.");
    else setProfileError(null);
  }, []);

  const refreshProfile = useCallback(async () => {
    const userId = session?.user.id;
    if (!supabase || !userId) return;
    setLoading(true);
    try {
      await readProfile(userId);
    } catch (error) {
      setProfileError(friendlyBackendError(error).message);
    } finally {
      setLoading(false);
    }
  }, [readProfile, session?.user.id]);

  useEffect(() => {
    if (!supabase) {
      setLoading(false);
      return;
    }

    let alive = true;
    let activeUserId: string | null = null;
    const client = supabase;
    const readForSession = async (userId: string) => {
      try {
        const { data, error } = await client
          .from("profiles")
          .select("user_id, app_role, display_name, created_at, updated_at")
          .eq("user_id", userId)
          .maybeSingle();
        if (!alive || activeUserId !== userId) return;
        if (error) throw error;
        setProfile(data);
        setProfileError(data ? null : "Your profile is still being provisioned. Try refreshing in a moment.");
      } catch (error) {
        if (!alive || activeUserId !== userId) return;
        setProfile(null);
        setProfileError(friendlyBackendError(error).message);
      } finally {
        if (alive && activeUserId === userId) setLoading(false);
      }
    };

    const applySession = (next: Session | null) => {
      activeUserId = next?.user.id ?? null;
      setSession(next);
      setProfile(null);
      setProfileError(null);
      if (!next) {
        setLoading(false);
        return;
      }
      setLoading(true);
      window.setTimeout(() => void readForSession(next.user.id), 0);
    };

    const { data: authListener } = client.auth.onAuthStateChange((_event, next) => applySession(next));
    void client.auth.getSession().then(({ data, error }) => {
      if (!alive) return;
      if (error) {
        setProfileError(friendlyBackendError(error).message);
        setLoading(false);
        return;
      }
      applySession(data.session);
    });

    return () => {
      alive = false;
      authListener.subscription.unsubscribe();
    };
  }, []);

  const value = useMemo(
    () => ({ session, profile, loading, profileError, refreshProfile }),
    [session, profile, loading, profileError, refreshProfile],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const value = useContext(AuthContext);
  if (!value) throw new Error("useAuth must be used within AuthProvider.");
  return value;
}
