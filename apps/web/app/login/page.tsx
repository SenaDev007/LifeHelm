"use client";

import { useState } from "react";
import { apiFetch } from "@/lib/api";
import { clearAccessToken, setAccessToken } from "@/lib/session";
import { useRouter } from "next/navigation";

export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState("test@lifehelm.app");
  const [password, setPassword] = useState("Test1234!");
  const [error, setError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(false);

  return (
    <div style={{ maxWidth: 420, margin: "60px auto", padding: 16 }}>
      <h1 style={{ margin: 0, fontSize: 28 }}>Connexion</h1>
      <p style={{ opacity: 0.8, marginTop: 8 }}>Prends le gouvernail de ta vie.</p>

      <div style={{ display: "grid", gap: 10, marginTop: 24 }}>
        <label style={{ display: "grid", gap: 6 }}>
          Email
          <input
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            style={{
              background: "rgba(255,255,255,0.06)",
              border: "1px solid rgba(255,255,255,0.14)",
              color: "white",
              padding: 12,
              borderRadius: 10,
            }}
          />
        </label>

        <label style={{ display: "grid", gap: 6 }}>
          Mot de passe
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            style={{
              background: "rgba(255,255,255,0.06)",
              border: "1px solid rgba(255,255,255,0.14)",
              color: "white",
              padding: 12,
              borderRadius: 10,
            }}
          />
        </label>

        {error ? (
          <div style={{ color: "#f87171", fontSize: 14 }}>{error}</div>
        ) : null}

        <button
          disabled={isLoading}
          onClick={async () => {
            clearAccessToken();
            setIsLoading(true);
            setError(null);
            try {
              const data = await apiFetch<{
                user: { id: string; name: string };
                accessToken: string;
              }>("/auth/login", {
                method: "POST",
                body: JSON.stringify({ email, password }),
              });
              setAccessToken(data.accessToken);
              router.push("/(accessible)/home");
            } catch (e) {
              setError(e instanceof Error ? e.message : "Erreur inconnue");
            } finally {
              setIsLoading(false);
            }
          }}
          style={{
            marginTop: 10,
            padding: "14px 16px",
            borderRadius: 12,
            border: "none",
            cursor: "pointer",
            background: "linear-gradient(90deg,#7c3aed,#2563eb)",
            color: "white",
            fontWeight: 700,
          }}
        >
          {isLoading ? "Connexion..." : "Se connecter"}
        </button>
      </div>
    </div>
  );
}

