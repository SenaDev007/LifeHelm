"use client";

import { useEffect, useMemo, useState } from "react";
import { apiFetch } from "@/lib/api";
import { getAccessToken } from "@/lib/session";

type ShopLog = {
  id: string;
  date: string;
  capitalMatin: number;
  recettes: number;
  reapprovisionnement: number;
  beneficeNet: number;
  note?: string | null;
};

function toISODate(d: Date) {
  const year = d.getFullYear();
  const month = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

export default function AccessibleDepensePage() {
  const todayISO = useMemo(() => toISODate(new Date()), []);
  const [log, setLog] = useState<ShopLog | null>(null);
  const [amount, setAmount] = useState<string>("2000");
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [isSaving, setIsSaving] = useState(false);

  useEffect(() => {
    const token = getAccessToken();
    if (!token) return;
    apiFetch<ShopLog | null>("/accessible/shop-log/today", { method: "GET", auth: true })
      .then((res) => setLog(res))
      .catch(() => setLog(null));
  }, []);

  const parsed = Number(amount);

  return (
    <div style={{ padding: 16, maxWidth: 560, margin: "0 auto" }}>
      <header style={{ padding: "20px 0 6px" }}>
        <div style={{ fontSize: 22, fontWeight: 900 }}>DEPENSE</div>
        <div style={{ opacity: 0.8, marginTop: 6 }}>{todayISO}</div>
      </header>

      <div style={{ marginTop: 20 }}>
        <div style={{ fontSize: 14, opacity: 0.85, marginBottom: 8 }}>
          Benefice net (calculé):{" "}
          <span style={{ fontWeight: 900 }}>{log ? `${Math.round(log.beneficeNet)} FCFA` : "—"}</span>
        </div>

        <label style={{ display: "grid", gap: 8 }}>
          <span style={{ fontSize: 14, opacity: 0.85 }}>Montant de reapprovisionnement (FCFA)</span>
          <input
            inputMode="numeric"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            style={{
              width: "100%",
              fontSize: 44,
              padding: "14px 14px",
              borderRadius: 18,
              background: "rgba(255,255,255,0.06)",
              border: "1px solid rgba(255,255,255,0.16)",
              color: "white",
              fontWeight: 900,
            }}
          />
        </label>

        {error ? <div style={{ color: "#f87171", marginTop: 12 }}>{error}</div> : null}
        {message ? <div style={{ color: "#34d399", marginTop: 12 }}>{message}</div> : null}

        <button
          disabled={isSaving || !Number.isFinite(parsed) || parsed < 0}
          onClick={async () => {
            setIsSaving(true);
            setError(null);
            setMessage(null);
            try {
              const body = log
                ? { reapprovisionnement: parsed }
                : {
                    date: todayISO,
                    capitalMatin: 0,
                    recettes: 0,
                    reapprovisionnement: parsed,
                  };

              const res = log
                ? await apiFetch<ShopLog>(`/accessible/shop-log/${log.id}`, {
                    method: "PATCH",
                    auth: true,
                    body: JSON.stringify(body),
                  })
                : await apiFetch<ShopLog>(`/accessible/shop-log`, {
                    method: "POST",
                    auth: true,
                    body: JSON.stringify(body),
                  });

              setLog(res);
              setMessage(`Enregistré: ${Math.round(parsed)} FCFA`);
              setAmount("0");
              window.setTimeout(() => setMessage(null), 2500);
            } catch (e) {
              setError(e instanceof Error ? e.message : "Erreur");
            } finally {
              setIsSaving(false);
            }
          }}
          style={{
            marginTop: 18,
            width: "100%",
            padding: "16px 16px",
            borderRadius: 18,
            border: "none",
            cursor: "pointer",
            background: "linear-gradient(90deg,#ef4444,#b91c1c)",
            color: "white",
            fontWeight: 900,
            fontSize: 18,
          }}
        >
          {isSaving ? "En cours..." : "ENREGISTRER"}
        </button>
      </div>
    </div>
  );
}

