"use client";

import { useEffect, useState } from "react";
import { apiFetch } from "@/lib/api";
import { getAccessToken } from "@/lib/session";

type ShopLog = {
  id: string;
  date: string;
  capitalMatin: number;
  recettes: number;
  reapprovisionnement: number;
  beneficeNet: number;
};

export default function AccessibleBilanPage() {
  const [log, setLog] = useState<ShopLog | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const token = getAccessToken();
    if (!token) return;
    apiFetch<ShopLog | null>("/accessible/shop-log/today", { method: "GET", auth: true })
      .then((res) => setLog(res))
      .catch((e) => setError(e instanceof Error ? e.message : "Erreur"));
  }, []);

  return (
    <div style={{ padding: 16, maxWidth: 560, margin: "0 auto" }}>
      <header style={{ padding: "20px 0 6px" }}>
        <div style={{ fontSize: 22, fontWeight: 900 }}>BILAN</div>
        <div style={{ opacity: 0.8, marginTop: 6 }}>{log?.date ?? "Aujourd'hui"}</div>
      </header>

      {error ? <div style={{ color: "#f87171" }}>{error}</div> : null}

      <div
        style={{
          marginTop: 18,
          background: "rgba(255,255,255,0.06)",
          border: "1px solid rgba(255,255,255,0.12)",
          borderRadius: 20,
          padding: 16,
          display: "grid",
          gap: 12,
        }}
      >
        <div style={{ display: "flex", justifyContent: "space-between", gap: 12 }}>
          <span style={{ opacity: 0.85 }}>Mise du matin</span>
          <span style={{ fontWeight: 900 }}>{log ? `${Math.round(log.capitalMatin)} FCFA` : "—"}</span>
        </div>
        <div style={{ display: "flex", justifyContent: "space-between", gap: 12 }}>
          <span style={{ opacity: 0.85 }}>Recettes</span>
          <span style={{ fontWeight: 900 }}>{log ? `${Math.round(log.recettes)} FCFA` : "—"}</span>
        </div>
        <div style={{ display: "flex", justifyContent: "space-between", gap: 12 }}>
          <span style={{ opacity: 0.85 }}>Réapprovisionnement</span>
          <span style={{ fontWeight: 900 }}>
            {log ? `${Math.round(log.reapprovisionnement)} FCFA` : "—"}
          </span>
        </div>
        <div style={{ display: "flex", justifyContent: "space-between", gap: 12, borderTop: "1px solid rgba(255,255,255,0.12)", paddingTop: 12 }}>
          <span style={{ opacity: 0.85 }}>Benefice net</span>
          <span style={{ fontWeight: 900, fontSize: 20 }}>
            {log ? `${Math.round(log.beneficeNet)} FCFA` : "—"}
          </span>
        </div>
      </div>
    </div>
  );
}

