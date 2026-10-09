import { useEffect, useMemo, useState } from "react";
import {
  Box,
  Clock3,
  LogOut,
  Palette,
  Settings as SettingsIcon,
  Sparkles,
} from "lucide-react";
import { api, type Session } from "../api/client";
import type { Catalog, Job, RenderDraft, Workspace } from "../api/types";
import { CreatePage } from "../features/CreatePage";
import { RecentPage } from "../features/RecentPage";
import { SettingsPage } from "../features/SettingsPage";
import { SpecimenPage } from "../features/SpecimenPage";
import { Button, TextField } from "../ui/Controls";
import { readTheme, THEMES, THEME_KEY, type ThemeId } from "../theme/themes";
type Route = "create" | "recent" | "settings" | "specimen";
const routeFromPath = (): Route =>
  location.pathname.endsWith("/recent")
    ? "recent"
    : location.pathname.endsWith("/settings")
      ? "settings"
      : location.pathname.endsWith("/specimen")
        ? "specimen"
        : "create";
export function App() {
  const [session, setSession] = useState<Session | null>(null),
    [catalog, setCatalog] = useState<Catalog | null>(null),
    [route, setRoute] = useState<Route>(routeFromPath),
    [theme, setTheme] = useState<ThemeId>(readTheme),
    [loginError, setLoginError] = useState(""),
    [draftSeed, setDraftSeed] = useState<Partial<RenderDraft> | null>(null),
    [defaultsVersion, setDefaultsVersion] = useState(0),
    [deletedWorkspaceId, setDeletedWorkspaceId] = useState<string>();
  useEffect(() => {
    api
      .session()
      .then(setSession)
      .catch(() => setSession({ authenticated: false }));
  }, []);
  useEffect(() => {
    if (
      session &&
      (session.authenticated ||
        session.auth_required === false ||
        session.auth_enabled === false)
    )
      api
        .catalog()
        .then(setCatalog)
        .catch(() => setCatalog(null));
  }, [session]);
  useEffect(() => {
    const fn = () => setRoute(routeFromPath());
    addEventListener("popstate", fn);
    return () => removeEventListener("popstate", fn);
  }, []);
  useEffect(() => {
    const prevent = (event: DragEvent) => event.preventDefault();
    document.addEventListener("dragover", prevent);
    document.addEventListener("drop", prevent);
    return () => {
      document.removeEventListener("dragover", prevent);
      document.removeEventListener("drop", prevent);
    };
  }, []);
  const density = THEMES.find((x) => x.id === theme)?.density ?? "compact";
  const authRequired = session
    ? (session.auth_required ?? session.auth_enabled ?? true)
    : true;
  const navigate = (next: Route) => {
    history.pushState({}, "", next === "create" ? "./" : `./${next}`);
    setRoute(next);
  };
  const chooseTheme = (value: ThemeId) => {
    setTheme(value);
    localStorage.setItem(THEME_KEY, value);
  };
  if (session === null)
    return (
      <main className="editor-shell boot-screen" data-editor-theme={theme}>
        Loading Sprite Extractor…
      </main>
    );
  if (authRequired && !session.authenticated)
    return (
      <main
        className="editor-shell login-screen"
        data-editor-theme={theme}
        data-editor-density={density}
      >
        <form
          className="login-card"
          onSubmit={async (e) => {
            e.preventDefault();
            const data = new FormData(e.currentTarget);
            try {
              setSession(
                await api.login(
                  String(data.get("username")),
                  String(data.get("password")),
                ),
              );
              setLoginError("");
            } catch (err) {
              setLoginError(
                err instanceof Error ? err.message : "Sign in failed.",
              );
            }
          }}
        >
          <div className="brand-mark">
            <Box />
          </div>
          <h1 className="editor-heading editor-heading--page">
            Sprite Extractor
          </h1>
          <p className="editor-text editor-text--secondary">
            Sign in to the server that runs your sprite generations.
          </p>
          <TextField
            label="Username"
            name="username"
            autoComplete="username"
            required
          />
          <TextField
            label="Password"
            name="password"
            type="password"
            autoComplete="current-password"
            required
          />
          {loginError && (
            <p role="alert" className="editor-text editor-text--danger">
              {loginError}
            </p>
          )}
          <Button variant="primary" type="submit">
            Sign in
          </Button>
        </form>
      </main>
    );
  return (
    <div
      className="editor-shell"
      data-editor-theme={theme}
      data-editor-density={density}
    >
      <header className="app-header">
        <button className="brand" onClick={() => navigate("create")}>
          <span className="brand-mark">
            <Box size={20} />
          </span>
          <span>
            <strong>Sprite Extractor</strong>
            <small>Character animation workshop</small>
          </span>
        </button>
        <nav aria-label="Main navigation">
          <button
            className={route === "create" ? "active" : ""}
            onClick={() => navigate("create")}
          >
            <Sparkles size={16} />
            Create sprites
          </button>
          <button
            className={route === "recent" ? "active" : ""}
            onClick={() => navigate("recent")}
          >
            <Clock3 size={16} />
            Recent renders
          </button>
          <button
            className={route === "settings" ? "active" : ""}
            onClick={() => navigate("settings")}
          >
            <SettingsIcon size={16} />
            Settings
          </button>
        </nav>
        <div className="header-actions">
          <label>
            <Palette size={15} />
            <span className="sr-only">Theme</span>
            <select
              aria-label="Theme"
              value={theme}
              onChange={(e) => chooseTheme(e.target.value as ThemeId)}
            >
              {THEMES.map((x) => (
                <option key={x.id} value={x.id}>
                  {x.label}
                </option>
              ))}
            </select>
          </label>
          {authRequired && (
            <Button
              compact
              icon
              aria-label="Sign out"
              title="Sign out"
              onClick={async () => {
                await api.logout();
                sessionStorage.removeItem("sprite-extractor.workspace");
                setDraftSeed(null);
                setSession({ authenticated: false });
              }}
            >
              <LogOut size={16} />
            </Button>
          )}
        </div>
      </header>
      <main className="app-main">
        <section hidden={route !== "create"}>
          <CreatePage
            catalog={catalog}
            defaultsVersion={defaultsVersion}
            deletedWorkspaceId={deletedWorkspaceId}
            initialDraft={draftSeed}
            onOpenSettings={() => navigate("settings")}
          />
        </section>{" "}
        {route === "recent" && (
          <RecentPage
            onWorkspaceDeleted={setDeletedWorkspaceId}
            onAdjust={(draft) => {
              setDraftSeed(draft);
              navigate("create");
            }}
          />
        )}
        {route === "settings" && (
          <SettingsPage
            theme={theme}
            onTheme={chooseTheme}
            onDefaultsSaved={() => setDefaultsVersion((x) => x + 1)}
          />
        )}{" "}
        {route === "specimen" && <SpecimenPage />}
      </main>
      <footer>
        <button onClick={() => navigate("specimen")}>UI specimen</button>
        <span>
          {authRequired && session.operator
            ? `Signed in as ${session.operator}`
            : !authRequired
              ? "Local network access"
              : ""}
        </span>
      </footer>
    </div>
  );
}
