"use client";

import { useState } from "react";
import { apiFetch } from "@/lib/api";
import { useRouter } from "next/navigation";
import { clearAccessToken, setAccessToken } from "@/lib/session";

export default function RegisterPage() {
  const router = useRouter();
  const [name, setName] = useState("Test User");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(false);

  return (
    <div style={{ maxWidth: 420, margin: "60px auto", padding: 16 }}>
      <h1 style={{ margin: 0, fontSize: 28 }}>Créer un compte</h1>
      <p style={{ opacity: 0.8, marginTop: 8 }}>Inscription en quelques secondes.</p>

      <div style={{ display: "grid", gap: 10, marginTop: 24 }}>
        <label style={{ display: "grid", gap: 6 }}>
          Nom
          <input
            value={name}
            onChange={(e) => setName(e.target.value)}
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
              }>("/auth/register", {
                method: "POST",
                body: JSON.stringify({ name, email, password }),
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
          {isLoading ? "Création..." : "Créer mon compte"}
        </button>
      </div>
    </div>
  );
}

